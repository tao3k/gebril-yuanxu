;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source write-file)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/source/directory module-directory-context)
        (only-in :yuanxu/module-system/source/admission
                 module-source-read yuanxu-default-module-style-policy
                 current-module-source-observer call-with-module-source-read-cache)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export module-candidate-stage-test with-other-source)

;; Core qualification scaffolding only; authors retain the ordinary fixture.
(def (with-other-source setup body)
  (with-publication-source
    (lambda (root first _source _view)
      (def other (path-expand "modules/custom/other" root))
      (for-each (lambda (role)
                  (write-file (path-expand role other)
                    (module-source-read (path-expand role first))))
                '("types.ss" "objects.ss" "config.ss"))
      (write-file (path-expand "interface.ss" other)
        "(.def Module identity: 'custom/other core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o greeting: Greeting)) features: (.o))")
      (setup root first other)
      (def init (path-expand "init.ss" root))
      (def view (yuanxu-load-modules
                  (if (file-exists? init) init (path-expand "modules" root))))
      (def locate (.get view context locate))
      (body root (locate 'custom/example) (locate 'custom/other) view))))

(def module-candidate-stage-test
  (test-suite "Unpublished candidate operations and complete Graph boundaries"
    (yuanxu-test-case "SDK enrollment follows first closure discovery, not repeated imports"
      (with-other-source
        (lambda (_root _first _other) (void))
        (lambda (root first other view)
          (def enrolled 0)
          (def requested 0)
          (def previous (current-module-source-observer))
          (parameterize
            ((current-module-source-observer
               (lambda (key amount)
                 (when (eq? key 'compiler-enrollment)
                   (set! enrolled (+ enrolled amount)))
                 (when (eq? key 'compiler-closure-requests)
                   (set! requested (+ requested amount)))
                 (when previous (previous key amount)))))
            (def reader (module-publication-reader))
            (.call reader read-candidate (lambda () first) 'custom/example (.get view context))
            (def first-enrolled enrolled)
            (def first-requested requested)
            (.call reader read-candidate (lambda () other) 'custom/other (.get view context))
            ;; Both declarations really execute their roles. Repeated SDK
            ;; demands retain fresh admission, without re-enrolling topology.
            (check-equal? (> first-enrolled 0) #t)
            (check-equal? (> requested first-requested) #t)
            (check-equal? enrolled first-enrolled)
            (.call reader admit-current)
            (write-file (path-expand "modules/custom/example/config.ss" root)
              "(def Greeting 42) (export Greeting)")
            (check-exception (.call reader admit-current) error?)))))
    (yuanxu-test-case "unrelated SourceRefs do not enlarge actual candidate filesystem work"
      (with-other-source
        (lambda (_root _first _other) (void))
        (lambda (root _first _other _view)
          ;; Exercise the real directory owner without the reader/SDK's
          ;; independent closure. This is a work control, not a capacity gate.
          (def context (module-directory-context (path-expand "modules" root) #f
                         publication-prepares-source?: #t))
          (def generation (.get context generation))
          (def previous (current-module-source-observer))
          (def (stat-work action)
            (def stats 0)
            (parameterize
              ((current-module-source-observer
                 (lambda (key amount)
                   (when (eq? key 'stats) (set! stats (+ stats amount)))
                   (when previous (previous key amount)))))
              (call-with-module-source-read-cache action))
            stats)
          (.call context locate 'custom/example)
          (def local-before
            (stat-work (lambda ()
                         (check-equal? (.call context candidate-current? generation 'custom/example) #t))))
          (def full-before
            (stat-work (lambda () (check-equal? (.call context current? generation) #t))))
          (.call context locate 'custom/other)
          (def local-after
            (stat-work (lambda ()
                         (check-equal? (.call context candidate-current? generation 'custom/example) #t))))
          (def full-after
            (stat-work (lambda () (check-equal? (.call context current? generation) #t))))
          (check-equal? (> local-before 0) #t)
          (check-equal? local-after local-before)
          (check-equal? (> full-after full-before) #t))))
    (yuanxu-test-case "candidate location checks actual support; full commit rejects a changed prior SourceRef"
      (with-other-source
        (lambda (_root _first _other) (void))
        (lambda (_root first _other view)
          (def context (.get view context))
          (def generation (.get context generation))
          (check-equal? (.call context candidate-current? generation 'custom/other) #t)
          ;; A native revision change, even to the same value, is stale. It is
          ;; unrelated to locating the OTHER unpublished candidate, but MUST
          ;; reject the full epoch and the changed SourceRef's own demand.
          (.put! first 'kind (.get first kind))
          (check-equal? (.call context candidate-current? generation 'custom/other) #t)
          (check-equal? (.call context candidate-current? generation 'custom/example) #f)
          (check-equal? (.call context current? generation) #f))))
    (yuanxu-test-case "cached snapshots still validate actual path kinds before full namespace commit"
      (with-other-source
        (lambda (_root _first _other) (void))
        (lambda (root _first _other view)
          (def context (.get view context))
          (def generation (.get context generation))
          ;; An unrelated namespace change stays tentative; actual requested
          ;; path changes must reject even though its snapshot was cached.
          (write-file (path-expand "modules/custom/new-name" root) "changed")
          (check-equal? (.call context candidate-current? generation 'custom/other) #t)
          (check-equal? (.call context current? generation) #f)
          (delete-file (path-expand "modules/custom/other/interface.ss" root))
          (check-equal? (.call context candidate-current? generation 'custom/other) #f)
          (check-equal? (.call context current? generation) #f))))
    (yuanxu-test-case "source discovery is inert and actual role execution remains on demand"
      (with-other-source
        (lambda (root first _other)
          (write-file (path-expand "config.ss" first)
            (string-append "(call-with-output-file "
              (object->string (path-expand "initialized" root))
              " (lambda (p) (display \"yes\" p))) (def Greeting \"hello\") (export Greeting)")))
        (lambda (root first _other view)
          (def reader (module-publication-reader))
          (def prepared (.call reader discover first))
          (check-equal? (file-exists? (path-expand "initialized" root)) #f)
          (check-equal? (.get prepared identity) 'custom/example)
          (def result (.call reader read-candidate (lambda () first) 'custom/example (.get view context)))
          (check-equal? (file-exists? (path-expand "initialized" root)) #t)
          (check-equal? (eq? (cadr result) (.get (caddr result) candidate)) #t)
          (check-equal? (.get (cadr result) identity) 'custom/example)
          (.call reader admit-current))))
    (yuanxu-test-case "foreign source effects remain tentative and fail the complete final boundary"
      (with-other-source
        (lambda (_root first other)
          (write-file (path-expand "config.ss" other)
            (string-append "(call-with-output-file (list path: "
              (object->string (path-expand "config.ss" first))
              " truncate: #t) (lambda (p) (display \"(def Greeting 42) (export Greeting)\" p))) "
              "(def Greeting \"other\") (export Greeting)")))
        (lambda (_root first other view)
          (def reader (module-publication-reader))
          (def context (.get view context))
          (def initial (.call reader read-candidate (lambda () first) 'custom/example context))
          (def pending (.call reader read-candidate (lambda () other) 'custom/other context))
          (check-equal? (.get (cadr pending) identity) 'custom/other)
          ;; A local receipt is not authority to publish the selected Graph.
          (check-exception (.call reader admit-current) error?)
          (check-equal? (.get (cadr initial) identity) 'custom/example))))
    (yuanxu-test-case "open Context calls have complete before and sticky after guards"
      (for-each
        (lambda (when-change)
          (with-other-source
            (lambda (_root _first _other) (void))
            (lambda (root first other view)
              (def reader (module-publication-reader))
              (def baseline (.get view context))
              (.call reader read-candidate (lambda () first) 'custom/example baseline)
              (def file (path-expand "modules/custom/example/config.ss" root))
              (def calls 0)
              (.def (Open @ baseline)
                .contract-obligations:
                (lambda (_contract _value)
                  (set! calls (+ calls 1))
                  (when (eq? when-change 'after)
                    (write-file file "(def Greeting 42) (export Greeting)"))
                  '()))
              (when (eq? when-change 'before)
                (write-file file "(def Greeting 42) (export Greeting)"))
              (check-exception
                (.call reader read-candidate (lambda () other) 'custom/other Open) error?)
              (check-equal? calls (if (eq? when-change 'before) 0 1)))))
        '(before after)))
    (yuanxu-test-case "a replaced source policy does not inherit candidate operation support"
      (with-other-source
        (lambda (_root _first _other) (void))
        (lambda (root first other view)
          (def reader (module-publication-reader))
          (.call reader read-candidate (lambda () first) 'custom/example (.get view context))
          (def policy yuanxu-default-module-style-policy)
          (def validate (.get policy validate))
          (def calls 0)
          (dynamic-wind
            (lambda ()
              (.put! policy 'validate
                (lambda args (set! calls (+ calls 1)) (apply validate args)))
              (write-file (path-expand "modules/custom/example/config.ss" root)
                "(def Greeting 42) (export Greeting)"))
            (lambda ()
              (check-exception
                (.call reader read-candidate (lambda () other) 'custom/other (.get view context)) error?)
              (check-equal? calls 0))
            (lambda () (.put! policy 'validate validate))))))))
