;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :std/error Error? Error-message)
        (only-in :clan/poo/number IntegerRange)
        (only-in :yuanxu/object-types/contracts yuanxu-classification-evidence)
        (only-in :yuanxu/admission/source SourceAdmissionContract. source-diagnose-at call-with-source-slot-reads)
        (only-in :yuanxu/configuration/slot-origin field-slot-origins/value)
        (only-in :yuanxu/module-system/source/admission
                 current-module-source-observer call-with-module-source-read-cache
                 module-source-admit-current!)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures
                 DirectoryFixture write-source read-overrides))
(export source-observation-test test-cleanup!)

;; Actual SDK expansion of a temporary Scheme file attaches native slot origins.
;; No fabricated location rows or caller-maintained observation sets.
(def (observed-config path text)
  (write-source path text)
  (read-overrides path '(Observed)))
(.def (ObservationContract @ SourceAdmissionContract.)
  ;; The adapter is production; only this domain-free classifier is a fixture.
  identity: 'test/source-observation
  .classify:
  (lambda (candidate context)
    (yuanxu-classification-evidence identity candidate #t '() context)))
(def Port (IntegerRange min: 1 max: 65535))
(def PortFields (.cc ObjectContract. responsibilities: (.o port: Port)))
(def completed 0)
(def (test-cleanup!)
  (unless (= completed 6) (error "incomplete source observation controls" completed))
  (displayln "SOURCE-OBSERVATION: 6 cases completed"))
(def source-observation-test
  (test-suite "Collect actual source checks without a field list"
    (yuanxu-test-fixture "replay shares one pure pass but never a preceding effect window"
      (fixture DirectoryFixture)
      (def path (path-expand "window.ss" (.get fixture root)))
      (def text "(.def Observed port: 5432 client: 5432)\n")
      (def candidate (observed-config path text))
      ;; Already-cached values still carry both original slot dependencies.
      (check-equal? (.get candidate port) 5432)
      (check-equal? (.get candidate client) 5432)
      (def replay-reads 0)
      (def (read-fields) (+ (.get candidate port) (.get candidate client)))
      (parameterize ((current-module-source-observer
                      (lambda (key amount)
                        (when (and (pair? key) (eq? (car key) 'file-read)
                                   (eq? (cadr key) 'slot-replay))
                          (set! replay-reads (+ replay-reads amount))))))
        (check-equal? (call-with-source-slot-reads read-fields) 10864)
        (check-equal? replay-reads 1)
        (check-equal? (call-with-source-slot-reads read-fields) 10864)
        ;; A new replay must read again, even for the same warmed receiver.
        (check-equal? replay-reads 2))
      (def failure
        (with-catch values
          (lambda ()
            (call-with-module-source-read-cache
              (lambda ()
                (module-source-admit-current! (list (cons path text)))
                (call-with-source-slot-reads
                  (lambda ()
                    (read-fields)
                    (write-source path "; changed after a cached source guard\n"))))))))
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "Scheme configuration source changed")
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "a guarded cached slot is rechecked and exceptions do not leak observations"
      (fixture DirectoryFixture)
      (def path (path-expand "selected.ss" (.get fixture root)))
      (def candidate (observed-config path "(.def Observed port: 5432)\n"))
      (check-equal? (.get candidate port) 5432)
      (def after-mutation-reads 0)
      (.def (Contract @ ObservationContract)
        .preflight: (source-diagnose-at PortFields '())
        .obligations:
        (lambda (_candidate _context)
          ;; Deliberate negative effect, never a normal domain obligation.
          (write-source path "(.def Observed port: 5440)\n")
          (.get _candidate port)
          (set! after-mutation-reads (+ after-mutation-reads 1))
          '()))
      (def failure (with-catch values (lambda () (.call Contract .admit candidate #f))))
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "Scheme configuration source changed")
      (check-equal? after-mutation-reads 0)
      (check-equal? (.get candidate port) 5432)
      ;; A fresh invocation must not inherit the failed scope's observations.
      (check-equal? (.get (.call ObservationContract .admit (.o) #f) accepted?) #t)
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "a nested JSON-only child reports its source to the outer admission"
      (fixture DirectoryFixture)
      (def path (path-expand "child.json" (.get fixture root)))
      (write-source path "{}")
      (def child-calls 0)
      (.def (Child @ ObservationContract)
        source-inputs: (list (cons path "{}"))
        .obligations: (lambda (_candidate _context)
                        (set! child-calls (+ child-calls 1)) '()))
      (.def (Root @ ObservationContract) responsibilities: (.o child: Child))
      (def candidate (.o child: (.o)))
      (def first (.call Root .admit candidate #f))
      (check-equal? (.get first accepted?) #t)
      (check-equal? (eq? (.get (car (.get first responsibility-evidence)) candidate)
                        (.get candidate child)) #t)
      (.def (Changing @ Root)
        .obligations: (lambda (_candidate _context)
                        (write-source path "{\"changed\":true}") '()))
      (def failure (with-catch values (lambda () (.call Changing .admit candidate #f))))
      (check-equal? child-calls 2)
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "configuration source changed")
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "unselected branch sources and values are not collected"
      (fixture DirectoryFixture)
      (def selected-path (path-expand "selected.ss" (.get fixture root)))
      (def unused-path (path-expand "unused.ss" (.get fixture root)))
      (def candidate
        (.o selected: (observed-config selected-path "(.def Observed port: 5432)\n")
            unused: (observed-config unused-path
                      "(.def Observed port: (error \"unused field must remain cold\"))\n")))
      ;; Construct both branches; only selected's field is admitted. Editing
      ;; unused after construction would refuse if it had been enrolled.
      (def unused-object (.get candidate unused))
      (.def (Contract @ ObservationContract)
        .preflight: (source-diagnose-at PortFields '(selected))
        .obligations: (lambda (_candidate _context)
                        (write-source unused-path "; unselected source changed\n") '()))
      (check-equal? (.get (.call Contract .admit candidate #f) accepted?) #t)
      (check-equal? (.get candidate selected port) 5432)
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "diagnostic-only checks finish within collection before refusal returns"
      (fixture DirectoryFixture)
      (def path (path-expand "diagnostic.ss" (.get fixture root)))
      (def candidate (observed-config path "(.def Observed port: 5432)\n"))
      (def issue (.o kind: 'test-refusal path: '(port)))
      (def locations 0)
      (.def (Contract @ ObservationContract)
        .preflight: (lambda (_candidate _path) (list issue))
        .locate-diagnostic:
        (lambda (value failure)
          (field-slot-origins/value value '(port))
          (set! locations (+ locations 1))
          ;; Both diagnostic lists have been observed before this mutation.
          (when (= locations 2) (write-source path "; changed after locating\n"))
          failure))
      (def failure (with-catch values (lambda () (.call Contract .admit candidate #f))))
      (check-equal? locations 2)
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "Scheme configuration source changed")
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "a later revision of the same path cannot replace an earlier observation"
      (fixture DirectoryFixture)
      (def path (path-expand "revision.ss" (.get fixture root)))
      (def first (observed-config path "(.def Observed port: 5432)\n"))
      (def classified 0)
      (.def (Contract @ ObservationContract)
        .preflight:
        (lambda (_candidate _path)
          (.get first port)
          (def second (observed-config path "(.def Observed port: 5440)\n"))
          (check-equal? (.get second port) 5440)
          '())
        (.classify (inherited)
          (lambda (candidate context)
            (set! classified (+ classified 1))
            ((inherited) candidate context))))
      (def failure (with-catch values (lambda () (.call Contract .admit (.o) #f))))
      (check-equal? classified 1)
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "Scheme configuration source changed")
      (set! completed (+ completed 1)))))
