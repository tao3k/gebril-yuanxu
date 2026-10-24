;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native controls for the module adapter of the existing fixture macro.
(import :std/test :clan/poo/object
        (only-in :std/list/list iota)
        (only-in :std/source this-source-file)
        (only-in :clan/poo/mop call-with-slot-read-observer)
        (only-in :clan/poo/slot-observation slot-read-key)
        (only-in :yuanxu/module-system/building/test-observation ModuleTestingProfile.)
        (only-in :yuanxu/poo-clos/objects poo-clos-generic-function poo-clos-method
                 poo-clos-any-specializer make-effective-method make-invocation-frame)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 current-module-process-trace-budget)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-default-testing-case-profile yuanxu-test-observe
                 yuanxu-test-checkpoint)
        (only-in :yuanxu/observability/testing-fixture
                 yuanxu-test-fixture with-yuanxu-fixture))
(export module-test-observation-test)

(def released 0)
(def policy-evaluations 0)
(.def Resource
  .acquire: void
  .release: (lambda (_value) (set! released (+ released 1))))
(.def (Observed @ ModuleTestingProfile.) identity: 'tests/module-observation emit?: #t trace-enabled?: #t)

(def module-test-observation-test
  (test-suite "Case-owned module observation"
    (yuanxu-test-fixture "the hygienic policy expression is evaluated once"
      profile: (begin (set! policy-evaluations (+ policy-evaluations 1)) Observed)
      (resource Resource)
      (def active-profile 'author-value)
      (check-equal? (unbox (current-module-process-trace-budget)) 4)
      ;; This is observation state, not author fixture code or a global quota.
      (set-box! (current-module-process-trace-budget) 0)
      (check-equal? active-profile 'author-value)
      (check-equal? policy-evaluations 1))
    (yuanxu-test-fixture "source events contribute only scalar categories"
      profile: Observed (resource Resource)
      (check-equal? (unbox (current-module-process-trace-budget)) 4)
      (check-equal? (.get Observed heap-limit-bytes) 2147483648)
      (check-equal? (.get Observed live-growth-limit-bytes) 1073741824)
      (check-equal? (yuanxu-test-observe 'compiler-demand 0) 0)
      ;; This test-only payload must neither become a key nor reach output.
      ((current-module-source-observer) (list 'compiler-demand (.o secret: 'probe)) 1)
      (check-equal? (yuanxu-test-observe 'compiler-demand 0) 1)
      ((current-module-source-observer) 'file-reads 3)
      (check-equal? (yuanxu-test-observe 'file-reads 0) 3)
      ((current-module-source-observer)
        '(package-process-observation (nix-gc-root-requests . 4) (nix-store-info-requests . 2)) 1)
      (check-equal? (yuanxu-test-observe 'nix-gc-root-requests 0) 4)
      (check-equal? (yuanxu-test-observe 'nix-store-info-requests 0) 2)
        ;; Distinct modules must not collapse to the same role basename.
        (def root (path-expand ".." (path-directory (this-source-file))))
        (def labels
          (call-with-output-string
            (lambda (port)
              (parameterize ((current-output-port port))
                (for-each
                  (lambda (name)
                    (def path (path-expand name root))
                    ((current-module-source-observer) (list 'native-source-import-start path) 1)
                    ((current-module-source-observer) (list 'native-source-import-end path) 1))
                  '("modules/nix/func.ss" "modules/funflow/func.ss"))))))
        (check-equal? (and (string-contains labels "modules/nix/func.ss") #t) #t)
        (check-equal? (and (string-contains labels "modules/funflow/func.ss") #t) #t)
        (check-equal? (string-contains labels (path-normalize root)) #f)
      ((current-module-source-observer) 'check-seconds 0.000002)
      (check-equal? (yuanxu-test-observe 'check-microseconds 0) 2)
      ;; Closed timing categories use existing scalar Case counters, and do
      ;; not retain the reader's syntax, token graph or compiled program.
      (for-each
        (lambda (keys)
          ((current-module-source-observer) (list (car keys) 'body) 1)
          ((current-module-source-observer) (list (cadr keys) 'body) 1)
          ;; Private span totals do not occupy the Case's domain categories.
          (check-equal? (yuanxu-test-observe (caddr keys) 0) 0))
        '((reader-compile-start reader-compile-end reader-compile-microseconds)
          (reader-eval-start reader-eval-end reader-eval-microseconds)
          (metadata-replay-start metadata-replay-end metadata-replay-microseconds)
          (reader-location-start reader-location-end reader-location-microseconds)
          (reader-preparation-start reader-preparation-end reader-preparation-microseconds)
          (reader-interface-start reader-interface-end reader-interface-microseconds)
          (reader-admission-start reader-admission-end reader-admission-microseconds)
          (reader-projection-start reader-projection-end reader-projection-microseconds)))
      (check-equal? (.get (yuanxu-test-checkpoint 'selected) after phase) 'selected)
      (check-exception
        ((current-module-source-observer) (list 'reader-retention (cons 'bad (.o))) 1)
        error?))
    (yuanxu-test-fixture "a new macro invocation has independent totals"
      profile: Observed (resource Resource)
      (check-equal? (yuanxu-test-observe 'compiler-demand 0) 0))
    (yuanxu-test-fixture "read-width tracing preserves every native observer delivery"
      profile: Observed (resource Resource)
      (def target (.o answer: 42))
      (check-equal? (.get target answer) 42)
      (def deliveries 0)
      (call-with-slot-read-observer
        (lambda (read)
          (when (eq? (slot-read-key read) 'answer)
            (set! deliveries (+ deliveries 1))))
        (lambda ()
          (check-equal? (.get target answer) 42)
          (check-equal? (.get target answer) 42)))
      (check-equal? deliveries 2))
    (test-case "receipt attribution never demands cold Contract or Context slots"
      ;; Observation-only probes, not valid admission receipts. A census may
      ;; inspect cached kind data but must not validate or activate these values.
      (def descriptors
        (map (lambda (n)
               (.o kind: 'yuanxu.contract.validation-evidence
                   admission-contract: (error "observer forced Contract")
                   context: (error "observer forced Context")
                   ordinal: n)) (iota 128)))
      (for-each (lambda (value) (.get value kind)) descriptors)
      (def projected (.o selected-graph: (map (cut .ref <> 'ordinal) descriptors)))
      (def output
        (call-with-output-string
          (lambda (port)
            (parameterize ((current-output-port port))
              (.call Observed .run Observed "cold receipt fields"
                (lambda ()
                  (check-equal? (length (.get projected selected-graph)) 128)))))))
      (check-equal? (and (string-contains output "slot-dependency-contracts key=selected-graph") #t) #t)
      (for-each
        (lambda (value)
          (check-equal? (.ref/cached value 'admission-contract) #f)
          (check-equal? (.ref/cached value 'context) #f)) descriptors))
    (test-case "cached prototype census recognizes carriers without demanding their kind"
      (def frame #f)
      (def output
        (call-with-output-string
          (lambda (port)
            (parameterize ((current-output-port port))
              (.call Observed .run Observed "carrier prototype census"
                (lambda ()
                  (def generic (poo-clos-generic-function 'observed-carrier 1))
                  (def method
                    (poo-clos-method 'observed-method (list (poo-clos-any-specializer))
                      (lambda (_frame _value) 'done)))
                  (def args '(payload))
                  (def effective (make-effective-method generic args '() '() (list method) '()))
                  (set! frame (make-invocation-frame effective args #f 'primary method))
                  (check-equal? (.ref/cached effective 'kind) #f)
                  (check-equal? (.ref/cached frame 'kind) #f)))))))
      (check-equal? (and (string-contains output
        "reader-clos-roots publications=0 effective=1 frames=1") #t) #t)
      (check-equal? (.ref/cached frame 'kind) #f))
    (test-case "native read telemetry preserves the Case category budget"
      (def output
        (call-with-output-string
          (lambda (port)
            (parameterize ((current-output-port port))
              (.call Observed .run Observed "full category budget"
                (lambda ()
                  ;; Module authors retain the existing full work budget.
                  ;; Trace finalization must not allocate extra categories.
                  ((current-module-source-observer) 'public-preparation-requests 48)
                  ((current-module-source-observer) 'public-preparation-walks 1)
                  ((current-module-source-observer) 'kernel-closure-requests 9)
                  ((current-module-source-observer) 'kernel-closure-walks 3)
                  ((current-module-source-observer) 'kernel-context-visits 7)
                  ((current-module-source-observer)
                    '(reader-binding-roots (publications . 1)
                      (private-bindings . 13) (evaluated-interface-bindings . 223)
                      (private-code-bodies . 0)) 1)
                  (let loop ((index 0))
                    (when (< index 64)
                      (yuanxu-test-observe
                        (string->symbol (string-append "work-" (number->string index))) 1)
                      (loop (+ index 1))))))))))
      (check-equal? (and (string-contains output "slot-read-summary deliveries=") #t) #t)
      (check-equal? (and (string-contains output
        "public-source-preparation requests=48 preparations=1") #t) #t)
      (check-equal? (and (string-contains output
        "kernel-source-closure requests=9 walks=3 visits=7") #t) #t))
    (test-case "disabled observation preserves the original observer"
      (def previous (lambda (_key _amount) (void)))
      (parameterize ((current-module-source-observer previous))
        (defvalues (_value _receipt)
          (.call ModuleTestingProfile. .run ModuleTestingProfile. "inert observation"
            (lambda ()
              (check-equal? (eq? previous (current-module-source-observer)) #t)
              (check-equal? (current-module-process-trace-budget) #f)
              (check-equal? (yuanxu-test-observe 'file-reads 0) 0))))
        (check-equal? (eq? previous (current-module-source-observer)) #t)))
    (test-case "physical reads retain owner, phase and effect-boundary attribution"
      (def output
        (call-with-output-string
          (lambda (port)
            (parameterize ((current-output-port port))
              (.call Observed .run Observed "physical read attribution"
                (lambda ()
                  (def observer (current-module-source-observer))
                  (def root (path-normalize (path-expand ".." (path-directory (this-source-file)))))
                  (observer '(package-stage-start inputs-current) 1)
                  (observer '(publication-guard-start declaration-after) 1)
                  (observer (list 'file-read 'publication-current
                              (path-expand "modules/funflow/types.ss" root)) 3)
                  (observer '(publication-guard-end declaration-after) 1)
                  (observer '(package-stage-end inputs-current) 1)
                  (observer (list 'file-read 'compiler-import
                              (path-expand "modules/json-schema/objects.ss" root)) 2)))))))
      (check-equal? (and (string-contains output
        "phase=publication-current boundary=declaration-after owner=\"modules/funflow\" reads=3") #t) #t)
      (check-equal? (and (string-contains output
        "phase=compiler-import boundary=outside-guard owner=\"modules/json-schema\" reads=2") #t) #t)
      (check-equal? (and (string-contains output
        "source-effect kind=package-stage-start boundary=inputs-current reads=3") #t) #t)
      (check-equal? (and (string-contains output
        "source-effect kind=outside-effect boundary=source reads=2") #t) #t))
    (test-case "body failure releases its fixture and restores observer scope"
      (def previous (current-module-source-observer))
      (def before released)
      (check-exception
        (.call Observed .run Observed "deliberate failure"
          (lambda ()
            (with-yuanxu-fixture (resource Resource)
              (error "deliberate body failure")))) error?)
      (check-equal? released (+ before 1))
      (check-equal? (eq? previous (current-module-source-observer)) #t)
      (check-equal? (current-module-process-trace-budget) #f)
      (check-equal? (yuanxu-test-observe 'file-reads 0) 0))
    (yuanxu-test-fixture "automatic observation contributes no domain slot reads"
      profile: Observed (resource Resource)
      (def reads '())
      (call-with-slot-read-observer
        (lambda (read) (set! reads (cons read reads)))
        (lambda ()
          ((current-module-source-observer) '(admission-stage-start contract-admit) 1)
          ((current-module-source-observer) '(admission-stage-end contract-admit) 1)
          ((current-module-source-observer) '(package-store-validity hit) 1)
          ((current-module-source-observer) '(native-source-import-start "outer.ss") 1)
          ((current-module-source-observer) '(native-source-import-start "inner.ss") 1)
          ((current-module-source-observer) '(native-source-import-end "inner.ss") 1)
          ;; Only the completed outer span contributes time, not both edges.
          (check-equal? (yuanxu-test-observe 'import-microseconds 0) 0)
          ((current-module-source-observer) '(native-source-import-end "outer.ss") 1)
          ((current-module-source-observer) '(reader-declaration (bindings . 1) (imports . 0)) 1)))
      (check-equal? reads '())
      (check-equal? (>= (yuanxu-test-observe 'import-microseconds 0) 0) #t)
      (check-equal? (>= (yuanxu-test-observe 'import-cpu-microseconds 0) 0) #t))
    (test-case "native Ops flags follow the shared default heap"
      (check-equal? (.get yuanxu-default-testing-case-profile heap-limit-bytes)
                    2147483648))))
