;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Production return-currentness events; known misses remain expected witnesses.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/object-types/contracts yuanxu-classification-evidence)
        (only-in :yuanxu/admission/source SourceAdmissionContract.)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 current-module-source-phase module-source-read module-source-admit-current!)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures
                 DirectoryFixture ServicesFixture write-source))
(export source-admission-tail-test test-cleanup!)
(def completed 0)
(def (test-cleanup!)
  (check-equal? completed 6)
  (displayln "SOURCE-ADMISSION-TAIL: 6 cases completed"))
(def (tail-probe paths)
  (.def Subject port: 5432 unused: (error "unselected branch forced"))
  (.def Dependency port: 5432)
  (def checked-values (box '()))
  (.def (Descriptor @ SourceAdmissionContract.)
    identity: 'test/return-tail
    marker: 0
    source-inputs: (map (lambda (path) (cons path "{}")) paths)
    .classify: (lambda (candidate context)
                 (yuanxu-classification-evidence identity candidate #t '() context))
    .obligations:
    (lambda (candidate _context)
      (def sampled (list (.get Descriptor marker) (.get candidate port) (.get Dependency port)))
      (set-box! checked-values sampled)
      (if (equal? sampled '(0 5432 5432)) '()
        (list (.o kind: 'probe-policy)))))
  (.o contract: Descriptor candidate: Subject external: Dependency checked: checked-values))
(def (event-kind key) (if (pair? key) (car key) key))
;; This schedules effects from actual public production events, not a simulated
;; phase marker or replacement admission/replay/source-check implementation.
(def (at-event contract candidate context phase kind effect (path #f))
  (def prior (current-module-source-observer))
  (def did-fire? #f)
  (def actual-event #f)
  (def result-value
    (with-catch values
      (lambda ()
        (parameterize ((current-module-source-observer
                        (lambda (key amount)
                          (when prior (prior key amount))
                          (when (and (not did-fire?)
                                     (eq? (current-module-source-phase) phase)
                                     (eq? (event-kind key) kind)
                                     (or (not path) (and (pair? key) (equal? (caddr key) path))))
                            (set! did-fire? #t)
                            (set! actual-event key)
                            (effect)))))
          (.call contract .admit candidate context)))))
  (check-equal? did-fire? #t)
  (.o outcome: result-value event: actual-event))
(def (requires-error outcome message)
  (check-equal? (Error? outcome) #t)
  (check-equal? (Error-message outcome) message))
(def source-admission-tail-test
 (test-suite "Final source pass is not an object or multi-file transaction"
  (yuanxu-test-fixture "context callback before replay is caught by the real MOP sweep"
    (fixture DirectoryFixture)
    (def path (path-expand "input.json" (.get fixture root)))
    (write-source path "{}")
    (def probe (tail-probe (list path)))
    (def dependency (.get probe external))
    (def context (.o admit-current: (lambda () (.putslot! dependency 'port ($constant-slot-spec 5433)))))
    (def result (with-catch values (cut .call (.get probe contract) .admit (.get probe candidate) context)))
    (requires-error result "stale slot dependency")
    (check-equal? (.get dependency port) 5433)
    (set! completed (+ completed 1)))
  (yuanxu-test-fixture "observer at replay entry is still caught"
    (fixture DirectoryFixture)
    (def path (path-expand "input.json" (.get fixture root)))
    (write-source path "{}")
    (def probe (tail-probe (list path)))
    (def dependency (.get probe external))
    (def result
      (at-event (.get probe contract) (.get probe candidate) #f 'slot-replay 'checks
        (lambda () (.putslot! dependency 'port ($constant-slot-spec 5433)))))
    (requires-error (.get result outcome) "stale slot dependency")
    (set! completed (+ completed 1)))
  (yuanxu-test-fixture "post-replay source observer can change receiver candidate or external value without a second MOP sweep"
    (fixture DirectoryFixture)
    (def path (path-expand "input.json" (.get fixture root)))
    (for-each
      (lambda (target)
        (write-source path "{}")
        (def probe (tail-probe (list path)))
        (def Contract (.get probe contract))
        (def candidate (.get probe candidate))
        (check-equal? (.get (.call Contract .admit candidate #f) accepted?) #t)
        (def receiver (case target
                        ((receiver) Contract)
                        ((candidate) candidate)
                        ((external) (.get probe external))))
        (def key (if (eq? target 'receiver) 'marker 'port))
        (def before (object-revision receiver))
        (def result
          (at-event Contract candidate #f 'return-currentness 'file-read
            (lambda () (.putslot! receiver key ($constant-slot-spec (if (eq? target 'receiver) 1 5433)))) path))
        ;; Expected limitation witness, not a passing safety claim.
        (check-equal? (.get result outcome accepted?) #t)
        (check-equal? (unbox (.get probe checked)) '(0 5432 5432))
        (check-equal? (object-revision receiver) (+ before 1))
        (check-equal? (module-source-read path) "{}")
        ;; A subsequent independent admission sees the actual changed policy.
        (check-equal? (.get (.call Contract .admit candidate #f) accepted?) #f))
      '(receiver candidate external))
    (set! completed (+ completed 1)))
  (yuanxu-test-fixture "late source mismatch still rejects before return despite simultaneous object mutation"
    (fixture DirectoryFixture)
    (def path (path-expand "input.json" (.get fixture root)))
    (write-source path "{}")
    (def probe (tail-probe (list path)))
    (def dependency (.get probe external))
    (def result
      (at-event (.get probe contract) (.get probe candidate) #f 'return-currentness 'file-read
        (lambda ()
          (.putslot! dependency 'port ($constant-slot-spec 5433))
          (write-source path "{\"changed\":true}")) path))
    (requires-error (.get result outcome) "configuration source changed")
    (set! completed (+ completed 1)))
  (yuanxu-test-fixture "later file observer changes an already checked file and escapes the ordered final pass"
    (fixture DirectoryFixture)
    (def first (path-expand "first.json" (.get fixture root)))
    (def second (path-expand "second.json" (.get fixture root)))
    (write-source first "{}") (write-source second "{}")
    (def probe (tail-probe (list first second)))
    (def result
      (at-event (.get probe contract) (.get probe candidate) #f 'return-currentness 'file-read
        (lambda () (write-source first "{\"late\":true}")) second))
    (check-equal? (.get result outcome accepted?) #t)
    (check-equal? (module-source-read first) "{\"late\":true}")
    (requires-error
      (with-catch values
        (cut module-source-admit-current! (list (cons first "{}") (cons second "{}"))
             "configuration source changed"))
      "configuration source changed")
    (set! completed (+ completed 1)))
  (yuanxu-test-fixture "real service plan can become stale during final source inspection while requirements and parent remain"
    (fixture ServicesFixture)
    (def publication (.get fixture publication))
    (def Contract (.get publication contract))
    (def Context (.get publication context))
    (check-equal? (length (.get Context contributions)) 2)
    (def Parent (.get publication value))
    (def cached (.get Parent plan))
    (.def (Release @ Parent)
      config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
    (def analyzed #f)
    (def analyze (.get Context .contract-obligations))
    (def Observed
      (.cc Context .contract-obligations:
        (lambda (actual candidate)
          (def issues (analyze actual candidate))
          (when (eq? actual Contract) (set! analyzed candidate))
          issues)))
    (check-equal? (.get (.call Contract .admit Release Observed) accepted?) #t)
    (def result
      (at-event Contract Release Observed 'return-currentness 'file-read
        (lambda ()
          (check-equal? (object? analyzed) #t)
          (.putslot! (.get analyzed config postgresql settings) 'port ($constant-slot-spec 5440)))))
    (def evidence (.get result outcome))
    (check-equal? (.get evidence accepted?) #t)
    (check-equal? (eq? (.get evidence candidate) analyzed) #t)
    (check-equal? (.get analyzed config postgresql settings port) 5440)
    (check-equal? (.get analyzed plan postgresql port) 5433)
    (check-equal? (.get cached postgresql port) 5432)
    (check-equal? (eq? cached (.get Parent plan)) #t)
    (check-equal? (length (.get Context contributions)) 2)
    (set! completed (+ completed 1)))))
