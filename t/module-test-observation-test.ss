;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native controls for the module adapter of the existing fixture macro.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop call-with-slot-read-observer)
        (only-in :core/module-system/building/test-observation ModuleTestingProfile.)
        (only-in :core/module-system/source/admission current-module-source-observer
                 current-module-process-trace-budget)
        (only-in :core/observability/testing-case
                 poo-flow-default-testing-case-profile poo-flow-test-observe
                 poo-flow-test-checkpoint)
        (only-in :core/observability/testing-fixture
                 poo-flow-test-fixture with-poo-flow-fixture))
(export module-test-observation-test)

(def released 0)
(def policy-evaluations 0)
(.def Resource
  .acquire: void
  .release: (lambda (_value) (set! released (+ released 1))))
(.def (Observed @ ModuleTestingProfile.) identity: 'tests/module-observation emit?: #t trace-enabled?: #t)

(def module-test-observation-test
  (test-suite "Case-owned module observation"
    (poo-flow-test-fixture "the hygienic policy expression is evaluated once"
      profile: (begin (set! policy-evaluations (+ policy-evaluations 1)) Observed)
      (resource Resource)
      (def active-profile 'author-value)
      (check-equal? (unbox (current-module-process-trace-budget)) 4)
      ;; This is observation state, not author fixture code or a global quota.
      (set-box! (current-module-process-trace-budget) 0)
      (check-equal? active-profile 'author-value)
      (check-equal? policy-evaluations 1))
    (poo-flow-test-fixture "source events contribute only scalar categories"
      profile: Observed (resource Resource)
      (check-equal? (unbox (current-module-process-trace-budget)) 4)
      (check-equal? (.get Observed heap-limit-bytes) 2147483648)
      (check-equal? (.get Observed live-growth-limit-bytes) 1073741824)
      (check-equal? (poo-flow-test-observe 'compiler-demand 0) 0)
      ;; This test-only payload must neither become a key nor reach output.
      ((current-module-source-observer) (list 'compiler-demand (.o secret: 'probe)) 1)
      (check-equal? (poo-flow-test-observe 'compiler-demand 0) 1)
      ((current-module-source-observer) 'file-reads 3)
      (check-equal? (poo-flow-test-observe 'file-reads 0) 3)
      ((current-module-source-observer) 'check-seconds 0.000002)
      (check-equal? (poo-flow-test-observe 'check-microseconds 0) 2)
      (check-equal? (.get (poo-flow-test-checkpoint 'selected) after phase) 'selected)
      (check-exception
        ((current-module-source-observer) (list 'reader-retention (cons 'bad (.o))) 1)
        error?))
    (poo-flow-test-fixture "a new macro invocation has independent totals"
      profile: Observed (resource Resource)
      (check-equal? (poo-flow-test-observe 'compiler-demand 0) 0))
    (test-case "disabled observation preserves the original observer"
      (def previous (lambda (_key _amount) (void)))
      (parameterize ((current-module-source-observer previous))
        (defvalues (_value _receipt)
          (.call ModuleTestingProfile. .run ModuleTestingProfile. "inert observation"
            (lambda ()
              (check-equal? (eq? previous (current-module-source-observer)) #t)
              (check-equal? (current-module-process-trace-budget) #f)
              (check-equal? (poo-flow-test-observe 'file-reads 0) 0))))
        (check-equal? (eq? previous (current-module-source-observer)) #t)))
    (test-case "body failure releases its fixture and restores observer scope"
      (def previous (current-module-source-observer))
      (def before released)
      (check-exception
        (.call Observed .run Observed "deliberate failure"
          (lambda ()
            (with-poo-flow-fixture (resource Resource)
              (error "deliberate body failure")))) error?)
      (check-equal? released (+ before 1))
      (check-equal? (eq? previous (current-module-source-observer)) #t)
      (check-equal? (current-module-process-trace-budget) #f)
      (check-equal? (poo-flow-test-observe 'file-reads 0) 0))
    (poo-flow-test-fixture "automatic observation contributes no domain slot reads"
      profile: Observed (resource Resource)
      (def reads '())
      (call-with-slot-read-observer
        (lambda (read) (set! reads (cons read reads)))
        (lambda ()
          ((current-module-source-observer) '(admission-stage-start contract-admit) 1)
          ((current-module-source-observer) '(admission-stage-end contract-admit) 1)
          ((current-module-source-observer) '(nix-store-validity hit) 1)
          ((current-module-source-observer) '(native-source-import-start "outer.ss") 1)
          ((current-module-source-observer) '(native-source-import-start "inner.ss") 1)
          ((current-module-source-observer) '(native-source-import-end "inner.ss") 1)
          ;; Only the completed outer span contributes time, not both edges.
          (check-equal? (poo-flow-test-observe 'import-microseconds 0) 0)
          ((current-module-source-observer) '(native-source-import-end "outer.ss") 1)
          ((current-module-source-observer) '(reader-declaration (bindings . 1) (imports . 0)) 1)))
      (check-equal? reads '())
      (check-equal? (>= (poo-flow-test-observe 'import-microseconds 0) 0) #t)
      (check-equal? (>= (poo-flow-test-observe 'import-cpu-microseconds 0) 0) #t))
    (test-case "native Ops flags follow the shared default heap"
      (check-equal? (.get poo-flow-default-testing-case-profile heap-limit-bytes)
                    2147483648))))
