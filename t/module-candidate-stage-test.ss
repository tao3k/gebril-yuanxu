;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :gerbil/expander core-import-module module-context-path)
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source write-file)
        (only-in :yuanxu/modules/funflow/control-plane/task TaskContract)
        (only-in :yuanxu/modules/funflow/control-plane/flow FlowContract)
        (only-in :yuanxu/modules/funflow/scenario Scenario)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/source/directory module-directory-context)
        (only-in :yuanxu/module-system/source/admission
                 module-source-read yuanxu-default-module-style-policy
                 current-module-source-observer call-with-module-source-read-cache
                 call-with-module-source-operation-measurement)
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
    (yuanxu-test-case "Core functional definitions retain their admitted compiler context"
      (with-other-source
        (lambda (root first _other)
          (write-file (path-expand "init.ss" root)
            "(yuanxu! source: \"./modules\" mode: explicit :custom (example))")
          (write-file (path-expand "objects.ss" first)
            (call-with-output-string
              (lambda (port)
                (for-each (lambda (form) (write form port) (newline port))
                  '((import (only-in :clan/poo/object .o)
                            (only-in :yuanxu/modules/funflow/control-plane/task TaskContract)
                            (only-in :yuanxu/modules/funflow/control-plane/flow FlowContract)
                            (only-in :yuanxu/modules/funflow/scenario Scenario))
                    (def FixtureScope
                      (.o task-contract: TaskContract flow-contract: FlowContract scenario-type: Scenario))
                    (export FixtureScope)))))))
        (lambda (_root _first _other view)
          (defvalues (scope times)
            (call-with-module-source-operation-measurement
              (lambda () (.get view modules custom example))))
          (unless (current-module-source-observer)
            (check-equal? (hash-ref times '(calls reader-candidate-entry-replay) 0) 1)
            (check-equal? (hash-ref times '(calls reader-candidate-fused-return-replay) 0) 1)
            (check-equal? (hash-ref times '(calls reader-preparation-replay) 0) 0))
          (check-equal? (eq? (.get scope task-contract) TaskContract) #t)
          (check-equal? (eq? (.get scope flow-contract) FlowContract) #t)
          (check-equal? (eq? (.get scope scenario-type) Scenario) #t)
          (check-equal? (.ref/cached (.get view modules custom) 'other) #f)
          (def tool (core-import-module ':yuanxu/modules/funflow/control-plane/task))
          (def origin (module-context-path tool))
          ((.get view admit-current))
          (dynamic-wind
            (lambda () (slot-set! tool 'path (string-append origin ".changed")))
            (lambda ()
              (check-exception ((.get view admit-current))
                (lambda (failure)
                  (and (Error? failure)
                       (string-contains (Error-message failure) "compiler tool context changed")))))
            (lambda () (slot-set! tool 'path origin))))))
    (yuanxu-test-case "Gerbil enrollment follows first closure discovery, not repeated imports"
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
            ;; Both declarations really execute their roles. Repeated Gerbil
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
          ;; Exercise the real directory owner without the reader/Gerbil's
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
          ;; A runtime revision change, even to the same value, is stale. It is
          ;; unrelated to locating the OTHER unpublished candidate, but MUST
          ;; reject the full epoch and the changed SourceRef's own demand.
          (.put! first 'kind (.get first kind))
          (check-equal? (.call context candidate-current? generation 'custom/other) #t)
          (check-equal? (.call context candidate-current? generation 'custom/example) #f)
          (check-equal? (.call context current? generation) #f))))
    (yuanxu-test-case "full and candidate checks share revision support without sharing approval"
      (with-other-source
        (lambda (root _first _other)
          (write-file (path-expand "init.ss" root)
            "(yuanxu! source: \"./modules\" mode: explicit :custom (example) (other))"))
        (lambda (_root _first _other view)
          (def context (.get view context))
          (def generation (.get context generation))
          (def selection (.get (car (.get context intent decisions)) selection))
          (check-equal? (.call context current? generation) #t)
          (.put! selection 'enabled? (.get selection enabled?))
          (check-equal? (.call context candidate-current? generation 'custom/example) #f)
          (check-equal? (.call context candidate-current? generation 'custom/other) #t)
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
          (def location-calls 0)
          (defvalues (result times)
            (call-with-module-source-operation-measurement
              (lambda ()
                (.call reader read-candidate (lambda () first) 'custom/example
                  (.get view context) #f (lambda () (set! location-calls (1+ location-calls)))))))
          (check-equal? (> location-calls 1) #t)
          (check-equal? (hash-ref times '(calls reader-candidate-entry-replay) 0) 0)
          (check-equal? (hash-ref times '(calls reader-candidate-fused-return-replay) 0) 0)
          (check-equal? (hash-ref times '(calls reader-preparation-replay) 0) 1)
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
