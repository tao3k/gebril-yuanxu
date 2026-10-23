;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/module-system/source/admission module-source-admit-current!)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture write-source)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence)
        (only-in :yuanxu/admission/source SourceAdmissionContract.)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export contract-analysis-test test-cleanup!)

;; Counters stand for platform dispatch, not source certification. Real source
;; refusal and reader/link closure counts are separate consumer controls.
(def completed 0)
(def (test-cleanup!)
  (unless (= completed 5) (error "incomplete analysis ownership controls" completed)))
(def (accept candidate context)
  (yuanxu-classification-evidence 'analysis-control candidate #t '() context))
(def contract-analysis-test
  (test-suite "Root-owned responsibility analysis"
    (yuanxu-test-case "an overridden admit cannot reuse a consumed responsibility edge"
      (def guarded 0)
      (def analyzed 0)
      (def Child
        (.o (:: @ YuanxuContract.) identity: 'analysis-control .classify: accept
          (.admit (inherited)
            (lambda (candidate context)
              ((inherited) candidate context)
              ((inherited) candidate context)))))
      (def Root
        (.o (:: @ SourceAdmissionContract.) identity: 'analysis-root .classify: accept
          responsibilities: (.o child: Child)))
      (def Context
        (.o .contract-obligations:
          (lambda (contract _candidate)
            (when (eq? contract Child) (set! guarded (+ guarded 1))) '())
          .responsibility-obligations:
          (lambda (_contract _candidate) (set! analyzed (+ analyzed 1)) '())))
      (check-equal? (.get (.call Root .admit (.o child: (.o)) Context) accepted?) #t)
      (check-equal? guarded 1)
      (check-equal? analyzed 1)
      (set! completed (+ completed 1)))
    (yuanxu-test-fixture "child observations are rechecked after its effect before root return"
      (fixture DirectoryFixture)
      (def path (path-expand "child.json" (.get fixture root)))
      (write-source path "{}")
      (def Child
        (.o (:: @ YuanxuContract.) identity: 'analysis-control .classify: accept
          .obligations:
          (lambda (_candidate _context)
            (module-source-admit-current! (list (cons path "{}")) "child source changed")
            (write-source path "{\"changed\":true}")
            '())))
      (def Root
        (.o (:: @ SourceAdmissionContract.) identity: 'analysis-root .classify: accept
          responsibilities: (.o child: Child)))
      (def Context
        (.o .contract-obligations: (lambda (_contract _candidate) '())
          .responsibility-obligations: (lambda (_contract _candidate) '())))
      (def failure
        (with-catch values (lambda () (.call Root .admit (.o child: (.o)) Context))))
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "child source changed")
      (set! completed (+ completed 1)))
    (yuanxu-test-case "responsibilities retain all receipts and local obligations"
      (def checked '())
      (def analyzed '())
      (def obligations 0)
      (def Context
        (.o .contract-obligations:
          (lambda (contract _candidate) (set! checked (cons contract checked)) '())
          .responsibility-obligations:
          (lambda (contract _candidate) (set! analyzed (cons contract analyzed)) '())))
      (def Leaf
        (.o (:: @ YuanxuContract.) identity: 'analysis-control .classify: accept
          .obligations: (lambda (_candidate _context)
                          (set! obligations (+ obligations 1)) '())))
      (def Branch
        (.o (:: @ Leaf) responsibilities: (.o database: Leaf client: Leaf)))
      (def Root
        (.o (:: @ SourceAdmissionContract.) identity: 'analysis-root .classify: accept
          responsibilities: (.o config: Branch)))
      (def Value (.o config: (.o database: (.o port: 5433) client: (.o port: 5433))))
      (def Evidence (.call Root .admit Value Context))
      (check-equal? (.get Evidence accepted?) #t)
      (check-equal? obligations 3)
      (check-equal? checked (list Root))
      (check-equal? (length analyzed) 3)
      (def ConfigEvidence (car (.get Evidence responsibility-evidence)))
      (check-equal? (eq? (.get ConfigEvidence candidate) (.get Value config)) #t)
      (check-equal? (length (.get ConfigEvidence responsibility-evidence)) 2)
      ;; The same registered descriptor outside a responsibility edge is full.
      (.call Branch .admit (.get Value config) Context)
      (check-equal? (length checked) 4)
      (check-equal? (length analyzed) 3)
      (set! completed (+ completed 1)))
    (yuanxu-test-case "an independent admission inside an obligation is not analysis"
      (def independent 0)
      (def analysis 0)
      (def Other (.o (:: @ YuanxuContract.) identity: 'analysis-control .classify: accept))
      (def Context
        (.o .contract-obligations:
          (lambda (contract _candidate)
            (when (eq? contract Other) (set! independent (+ independent 1))) '())
          .responsibility-obligations:
          (lambda (_contract _candidate) (set! analysis (+ analysis 1)) '())))
      (def Child
        (.o (:: @ Other)
          .obligations:
          (lambda (candidate context) (.call Other .admit candidate context) '())))
      (def Root
        (.o (:: @ SourceAdmissionContract.) identity: 'analysis-root .classify: accept
          responsibilities: (.o child: Child)))
      (check-equal? (.get (.call Root .admit (.o child: (.o)) Context) accepted?) #t)
      (check-equal? independent 1)
      (check-equal? analysis 1)
      (set! completed (+ completed 1)))
    (yuanxu-test-case "a rejecting child still runs its obligation and keeps its identity"
      (def issue (.o kind: 'child-policy))
      (def Context
        (.o .contract-obligations: (lambda (_contract _candidate) '())
          .responsibility-obligations: (lambda (_contract _candidate) '())))
      (def Child
        (.o (:: @ YuanxuContract.) identity: 'analysis-control .classify: accept
          .obligations: (lambda (_candidate _context) (list issue))))
      (def Root
        (.o (:: @ SourceAdmissionContract.) identity: 'analysis-root .classify: accept
          responsibilities: (.o child: Child)))
      (def Value (.o child: (.o)))
      (def Evidence (.call Root .admit Value Context))
      (check-equal? (.get Evidence accepted?) #f)
      (def Receipt (car (.get Evidence responsibility-evidence)))
      (check-equal? (eq? (.get Receipt candidate) (.get Value child)) #t)
      (check-equal? (eq? (car (.get Receipt diagnostics)) issue) #t)
      (set! completed (+ completed 1)))))
