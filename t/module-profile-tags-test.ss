;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object "./qualification/module-scale/fixture.ss"
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :tao3k/yuanxu/module-system/source/directory module-directory-context)
        (only-in :tao3k/yuanxu/module-system/source/init module-interface-tags module-init-intent)
        (only-in :tao3k/yuanxu/module-system/source/admission call-with-module-source-operation-measurement
                 current-module-source-observer)
        (only-in :tao3k/yuanxu/observability/output yuanxu-write-observation-line!))
(export module-profile-tags-test)

(def (verify-profile-selection exports count root)
  (check-equal? (.ref/cached exports 'modules) #f)
  (def admitted (make-hash-table))
  (def scopes (make-hash-table-eq))
  (def (observe key amount)
    (when (pair? key)
      (case (car key)
        ((publication-start)
         (hash-update! admitted (cadr key) (cut + <> amount) 0))
        ((link-stage-start)
         (let (stage (cadr key))
           (when (and (pair? stage) (eq? (car stage) 'scope-factory))
             (hash-update! scopes (cadr stage) (cut + <> amount) 0)))))))
  (def started (real-time))
  (defvalues (plan times)
    (call-with-module-source-operation-measurement
      (lambda ()
        (parameterize ((current-module-source-observer observe))
          (.get exports modules module-1 plan)))
      accounting?: 'stages))
  (def elapsed (- (real-time) started))
  (check-equal? plan '(5432))
  (check-equal? (parameterize ((current-module-source-observer observe))
                  (eq? (.get exports modules module-1 plan) plan)) #t)
  (check-equal? (hash-length admitted) 2)
  (check-equal? (hash-length scopes) 2)
  (for-each (lambda (id)
              (def interface (path-expand (string-append "modules/" (symbol->string id) "/interface.ss") root))
              (check-equal? (hash-get admitted interface) 1)
              (check-equal? (hash-get scopes id) 1))
            '(module-0 module-1))
  (yuanxu-write-observation-line!
    "profile-first-get modules=%s wall=%s declarations=2 scopes=2" count elapsed)
  (def phase 'profile-interface-scan)
  (check-equal? (hash-get times (list 'calls phase)) 1)
  (yuanxu-write-observation-line!
    "profile-metadata modules=%s wall=%s cpu=%s" count (hash-ref times phase)
    (+ (hash-ref times (list 'cpu-user phase)) (hash-ref times (list 'cpu-system phase))))
  (def modules (.get exports modules))
  (check-equal? (.all-slots modules) '(module-1))
  ;; The provider has different tags, but its declared edge enrolls it
  ;; without exposing it as a Profile root.
  (check-equal? (.get exports tests selected-graph module-order) '(module-0 module-1))
  (call-with-output-file (path-expand "build.ss" root)
    (lambda (port) (write '(def build-entry 0) port)))
  (def targets (map cadr (.get exports std-make-spec)))
  (check-equal? (andmap (lambda (name)
                         (or (string-prefix? "modules/module-0/" name)
                             (string-prefix? "modules/module-1/" name))) targets) #t)
  (check-equal? (ormap (cut string-prefix? "modules/module-0/" <>) targets) #t)
  (check-equal? (ormap (cut string-prefix? "modules/module-1/" <>) targets) #t)
  (def current (.get exports admit-current))
  (def timing (##exec-stats current))
  (yuanxu-write-observation-line!
    "profile-currentness modules=%s wall=%s cpu=%s"
    count (cdr (assq 'real-time timing))
    (+ (cdr (assq 'user-time timing)) (cdr (assq 'sys-time timing))))
  ;; A previously excluded owner can change the root selection. The old
  ;; Profile must refuse rather than treating a past tag match as approval.
  (call-with-output-file
    (list path: (path-expand "modules/module-2/interface.ss" root) truncate: #t)
    (lambda (port)
      (write '(.def Module identity: 'module-2 tags: '(security audited)) port)))
  (check-exception (current) error?))

(.def (ProfileSelectionFixture @ RuntimeValueFixture)
  profile-selection?: #t
  poison-unselected?: #t
  .verify: verify-profile-selection)

(def module-profile-tags-test
  (test-suite "Literal Interface tags and Profile selection"
    (test-case "tags are data and ordinary Gerbil libraries stay libraries"
      (check-equal? (module-interface-tags "interface.ss" "(.def X tags: '(security audited))")
                    '(security audited))
      (check-equal? (module-interface-tags "interface.ss" "(export)") #f)
      (check-exception (module-interface-tags "interface.ss" "(.def X tags: (error \"not evaluated\"))") error?)
      (check-exception (module-interface-tags "interface.ss" "(.def X tags: '(security security))") error?)
      (check-exception (module-interface-tags "interface.ss" "(.def X tags: '())") error?)
      (check-exception (module-interface-tags "interface.ss" "(.def X identity: 'x)") error?))
    (test-case "named Profile carries its source window and literal selector"
      (def intent
        (module-init-intent
          '((yuanxu! :test-dir "./t" :load-modules "./modules" rename: Security
              mode: auto profile: security)) #f))
      (def window (car (.get intent windows)))
      (check-equal? (.get window mount) 'Security)
      (check-equal? (.get window profile) 'security)
      (check-exception
        (module-init-intent '((yuanxu! :test-dir "./t" mode: auto profile: security)) #f)
        error?))
    (test-case "category roots span windows while dependency-only windows may be empty"
      (call-with-temporary-directory "profile-windows-"
        (lambda (root)
          (def (write-source name text)
            (def path (path-expand name root))
            (create-directory* (path-directory path))
            (call-with-output-file path (cut display text <>)))
          (write-source "lab/tofu/interface.ss" "(.def Tofu tags: '(deployment))")
          (write-source "core/flow/interface.ss" "(.def Flow tags: '(workflow))")
          (def (declaration core-tag)
            (write-source "consumer/init.ss"
              (string-append
                "(yuanxu! :test-dir \"./t\" :load-modules \"../lab\" rename: Lab mode: auto profile: deployment"
                " :load-modules \"../core\" rename: Core mode: auto profile: " core-tag ")")))
          (declaration "deployment")
          ;; Exercise inert directory policy; real role admission is covered by
          ;; the scale case and Lab's cross-package OpenTofu consumer.
          (def context (module-directory-context (path-expand "consumer/init.ss" root) #f
                         publication-prepares-source?: #t))
          (check-equal? (.get context selected) '(tofu))
          (check-equal? (.call context eligible? 'flow) #t)
          (check-equal? (.call context eligible? 'tofu) #t)
          ;; Inert tag selection needs no package marker and cannot grant the
          ;; standard publication/compilation authority of a paired reader.
          (check-exception
            (.call context read-publication (.call context locate 'tofu)) error?)
          (def generation (.get context generation))
          (check-equal? (.call context current? generation) #t)
          (write-source "core/flow/interface.ss" ";;; changed text, same tags\n(.def Flow tags: '(workflow))")
          (check-equal? (.call context current? generation) #t)
          (write-source "core/flow/interface.ss" "(.def Flow tags: '())")
          (check-equal? (.call context current? generation) #f)
          (write-source "core/flow/interface.ss" "(.def Flow tags: '(deployment))")
          (check-equal? (.call context current? generation) #f)
          ;; A miss for a DIFFERENT category cannot hide behind deployment's hit.
          (declaration "missing")
          (check-exception (module-directory-context (path-expand "consumer/init.ss" root) #f) error?))))
    (declaration-scale-case "Profile roots are shared by scope, build and tests" 1000 ProfileSelectionFixture)))
