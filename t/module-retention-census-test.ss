;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :gerbil/expander __module-registry expander-context-table
                 module-context? module-context-code module-context-e
                 module-context-import module-context-export module-context-ns module-context-path)
        (only-in :gerbil/runtime/loader list-modules)
        (only-in :gerbil/runtime/gambit unbound-global-exception?)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads slot-read-dependencies slot-read-receiver)
        (only-in :yuanxu/t/qualification/retention/payload report-retained-reads)
        (only-in :yuanxu/poo-clos/types ClosEffectiveMethod ClosInvocationFrame)
        (only-in :yuanxu/t/qualification/module-scale/fixture DeclarationFixture)
        (only-in :yuanxu/module-system/building/test-observation ModuleTestingProfile.)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot yuanxu-debug-cpu-microseconds)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 module-source-style-policy-current?
                 call-with-module-source-operation-measurement))
(export module-retention-census-test)
(def (build-producer-ready?)
  ;; Check the real public procedure too: a runtime import may initialize a
  ;; defining context without loading its whole facade's runtime wrapper.
  (with-catch
    (lambda (cause) (if (unbound-global-exception? cause) #f (raise cause)))
    (lambda () (procedure? (eval 'yuanxu/module-system/source/build#module-build-graph)))))
(def (read-identities roots)
  (def identities (make-hash-table-eq))
  (let walk ((pending roots))
    (unless (null? pending)
      (let (read (car pending))
        (if (hash-key? identities read) (walk (cdr pending))
          (begin
            (hash-put! identities read #t)
            (walk (append (slot-read-dependencies read) (cdr pending))))))))
  identities)
(def (reader-contexts)
  (def owners (make-hash-table-eq weak-keys: #t))
  (hash-for-each
    (lambda (_key context)
      (when (and (module-context? context)
                 (let (namespace (module-context-ns context))
                   (and (string? namespace) (string-prefix? "publication-reader-" namespace))))
        (hash-update! owners context 1+ 0)))
    __module-registry)
  owners)
(def (report-reader-contexts size before)
  (def rows (make-hash-table-eq))
  (hash-for-each
    (lambda (context aliases)
      (unless (hash-key? before context)
        (let* ((path (module-context-path context))
               (role (cond ((string-suffix? "-interface.ss" path) 'interface)
                           ((string-suffix? "-types.ss" path) 'types)
                           (else 'other)))
               (row (or (hash-get rows role) (make-vector 10 0)))
               (initializer (module-context-e context))
               ;; Gambit's delay-promise state holds the result (or the state
               ;; itself while pending) and the thunk. Inspect it without force.
               (state (and (promise? initializer) (##promise-state initializer)))
               (resolved? (and state (not (eq? state (vector-ref state 0))))))
          ;; Count direct native state, without forcing the initializer or
          ;; following imports into shared library Contexts.
          (for-each
            (lambda (index amount) (vector-set! row index (+ (vector-ref row index) amount)))
            '(0 1 2 3 4 5 6 7 8 9)
            (list 1 aliases (hash-length (expander-context-table context))
                  (length (module-context-import context)) (length (module-context-export context))
                  (if (module-context-code context) 1 0)
                  (if state 1 0) (if resolved? 1 0)
                  (if (and state (vector-ref state 1)) 1 0)
                  (if (and resolved? (not (eq? (vector-ref state 0) (void)))) 1 0)))
          (hash-put! rows role row))))
    (reader-contexts))
  (displayln "RETENTION-READER-CONTEXTS modules=" size
    " fields=(contexts registry-aliases binding-entries imports exports code-bodies"
    " promises resolved-promises retained-thunks nonvoid-results)"
    " roles=" (hash->list rows))
  (for-each
    (lambda (role)
      (let (row (hash-get rows role))
        ;; The census permits future retirement of a registry alias. A live
        ;; completed Context must release its body and initializer thunk.
        (when row
          (check-equal? (vector-ref row 5) 0)
          (check-equal? (vector-ref row 7) (vector-ref row 6))
          (check-equal? (vector-ref row 8) 0))))
    '(interface types)))
(def (census fixture size (earlier #f))
  ;; This diagnostic is not a source/acceptance cache. Its values are weak, so
  ;; the next Case can observe liveness after this Fixture and stack unwind.
  (def lifetime (make-hash-table-eq weak-values: #t))
  (def prior-contexts (reader-contexts))
  ;; Actual runtime loader state, not a fixture flag or inferred field value.
  (check-equal? (assoc "yuanxu/module-system/source/build" (list-modules)) #f)
  (check-equal? (build-producer-ready?) #f)
  (def body-expansions 0)
  (def physical-reads 0)
  (def replay-starts '())
  (def replay-seconds 0)
  (def replay-calls 0)
  (def replay-visits 0)
  (def preparation-depth 0)
  (def preparation-captures 0)
  (def preparation-roots 0)
  (def query-stages '())
  (def open-boundaries (make-hash-table))
  (def (query-stage label action)
    (def stats (##exec-stats (lambda () (call-with-values action list))))
    ;; Retain scalar diagnostics only, never a second source/Graph root.
    (set! query-stages
      (cons (cons label
              (map (lambda (key) (assq key stats))
                '(real-time user-time sys-time gc-real-time nb-gcs minflt majflt)))
            query-stages))
    (apply values (cdr (assq 'result stats))))
  (def (phase label action)
    (set! query-stages '())
    (def started (current-jiffy))
    (def cpu (yuanxu-debug-cpu-microseconds))
    (def before-expansions body-expansions)
    (def before-reads physical-reads)
    (def before-replay replay-seconds)
    (def before-calls replay-calls)
    (def before-visits replay-visits)
    (def before-preparation-captures preparation-captures)
    (def before-preparation-roots preparation-roots)
    (def roots '())
    ;; Installed Gambit's own accounting covers the ENTIRE phase, including
    ;; initialization and GC outside the nested reader spans. It adds no read
    ;; observer or semantic cache. Preserve both original returned values.
    (def stats
      (##exec-stats
        (lambda ()
          (call-with-values
            (lambda ()
              (call-with-module-source-operation-measurement
                (lambda ()
                  (parameterize ((current-module-source-observer observe))
                    (defvalues (value reads) (%call-with-recorded-slot-reads action unique-roots?: #t))
                    (set! roots reads)
                    value))))
            list))))
    (defvalues (result times) (apply values (cdr (assq 'result stats))))
    (displayln "RETENTION-PHASE modules=" size " phase=" label
      " wall-us=" (inexact->exact (floor (* 1000000 (/ (- (current-jiffy) started) (jiffies-per-second)))))
      " cpu-us=" (- (yuanxu-debug-cpu-microseconds) cpu)
      " expansions=" (- body-expansions before-expansions)
      " physical-reads=" (- physical-reads before-reads))
    (displayln "RETENTION-ACCOUNT modules=" size " phase=" label
      " user=" (cdr (assq 'user-time stats)) " system=" (cdr (assq 'sys-time stats))
      " gc-wall=" (cdr (assq 'gc-real-time stats))
      " gc-user=" (cdr (assq 'gc-user-time stats))
      " gc-system=" (cdr (assq 'gc-sys-time stats))
      " collections=" (cdr (assq 'nb-gcs stats))
      " minor-faults=" (cdr (assq 'minflt stats))
      " major-faults=" (cdr (assq 'majflt stats))
      " signed-vm-account=" (cdr (assq 'bytes-allocated stats)))
    (for-each
      (lambda (row)
        (displayln "RETENTION-QUERY modules=" size " phase=" label
          " stage=" (car row) " metrics=" (cdr row)))
      (reverse query-stages))
    (displayln "RETENTION-REPLAY modules=" size " phase=" label
      " inclusive-seconds=" (- replay-seconds before-replay)
      " calls=" (- replay-calls before-calls)
      " visits=" (- replay-visits before-visits))
    (displayln "RETENTION-PREPARATION-ROOTS modules=" size " phase=" label
      " captures=" (- preparation-captures before-preparation-captures)
      " roots=" (- preparation-roots before-preparation-roots))
    (check-equal? preparation-depth 0)
    (displayln "RETENTION-OPEN modules=" size " phase=" label
      " states=" (hash->list open-boundaries))
    ;; Existing reader spans overlap: report them separately, never add them
    ;; into a fabricated total. No additional observer or retained read graph.
    (for-each
      (lambda (stage)
        (displayln "RETENTION-WORK modules=" size " phase=" label " stage=" stage
          " seconds=" (or (hash-get times stage) 0)
          " calls=" (or (hash-get times (list 'calls stage)) 0)
          " visits=" (or (hash-get times (list 'visits stage)) 0)))
      '(directory-context reader-bootstrap candidate-read
        reader-location-start reader-preparation-start reader-interface-start reader-admission-start
        reader-compile-start
        reader-eval-start metadata-replay reader-source-snapshot reader-current
        link-current selection-current))
    ;; Inspect AFTER the measured operation. An arbitrary live read observer
    ;; intentionally selects open Generic dispatch and cannot measure the
    ;; closed route. Runtime capture retains original roots without a callback.
    (let (identities (read-identities roots))
      ;; Diagnostic reachability only: ordinary admission above owns ALL
      ;; authentication. This walk never invokes a checker or grants acceptance.
      (displayln "RETENTION-ISSUED modules=" size " phase=" label " records=" (hash-length identities))
      (let ((owners (make-hash-table-eq))
            (effective (hash-get (object-%instance ClosEffectiveMethod) 'proto))
            (frame (hash-get (object-%instance ClosInvocationFrame) 'proto)))
        (check-equal? (and (object? effective) (object? frame)) #t)
        (hash-for-each
          (lambda (read _)
            (let* ((receiver (slot-read-receiver read))
                   (order (object-%precedence-list receiver)))
              (when (and order (not (eq? receiver effective)) (not (eq? receiver frame))
                         (or (memq effective order) (memq frame order)))
                (hash-put! owners receiver #t)))) identities)
        (displayln "RETENTION-CARRIERS modules=" size " phase=" label " instances=" (hash-length owners))
        (check-equal? (hash-length owners) 0))
      (hash-for-each (lambda (read _)
        (let* ((receiver (slot-read-receiver read))
               (fields (object-%instance receiver)))
          (when (and fields (hash-key? fields 'core)
                     (eq? (hash-get fields 'identity) 'module-0))
            (hash-put! lifetime 'publication receiver)))) identities)
      (report-retained-reads (list size label) identities))
    result)
  (def retention #f)
  (def previous (current-module-source-observer))
  (def (observe key amount)
    (def category (if (pair? key) (car key) key))
    (when (eq? category 'reader-body-expanded) (set! body-expansions (+ body-expansions amount)))
    (when (eq? category 'file-read) (set! physical-reads (+ physical-reads amount)))
    (when (eq? category 'reader-retention) (set! retention (cdr key)))
    (when (eq? category 'candidate-open-boundary)
      ;; The existing observer already runs here. Sample runtime metadata only;
      ;; never probe a slot, invoke a user check or retain a continuation.
      (hash-update! open-boundaries
        (list (cdr key) (module-source-style-policy-current?) (object-construction-current?))
        1+ 0))
    (case category
      ((reader-preparation-start) (set! preparation-depth (1+ preparation-depth)))
      ((reader-preparation-end) (set! preparation-depth (1- preparation-depth)))
      ((reader-read-roots)
       ;; The native recording frame reports the original root count. Count
       ;; only captures made during preparation, without retaining its tokens.
       (when (positive? preparation-depth)
         (set! preparation-captures (1+ preparation-captures))
         (set! preparation-roots (+ preparation-roots (cdr (assq 'stored-roots (cdr key)))))))
      ((metadata-replay-start)
       (set! replay-starts (cons (real-time) replay-starts))
       (set! replay-calls (1+ replay-calls)))
      ((metadata-replay-visits) (set! replay-visits (+ replay-visits amount)))
      ((metadata-replay-end)
       (set! replay-seconds (+ replay-seconds (- (real-time) (car replay-starts))))
       (set! replay-starts (cdr replay-starts))))
    (when previous (previous key amount)))
  (def (query-and-authenticate)
    (def source
      (query-stage 'source (lambda () (.get (.call (.get fixture exports tests) .select '(module-0)) source))))
    (def graph (query-stage 'graph (lambda () (.get source selected-graph))))
    (hash-put! lifetime 'source source)
    (query-stage 'authenticate (lambda () ((.get graph admit-current))))
    graph)
  (def graph (phase 'cold query-and-authenticate))
  (def cold-expansions body-expansions)
  (check-equal? (eq? graph (phase 'hot query-and-authenticate)) #t)
  (check-equal? body-expansions cold-expansions)
  (check-equal? replay-starts '())
  (check-equal? (assoc "yuanxu/module-system/source/build" (list-modules)) #f)
  (check-equal? (build-producer-ready?) #f)
  (def memory (yuanxu-debug-memory-snapshot 'retention-census collect?: #t))
  (check-equal? (length (.get graph module-order)) size)
  (check-equal? (.ref/cached (.get fixture modules) 'module-0) #f)
  ;; This fixture initializes one private Types role per Interface. The
  ;; Interface bodies complete too, but have no role transfer association.
  (check-equal? (cdr (assq 'private-contexts retention)) size)
  (check-equal? (cdr (assq 'transfer-initializers retention)) size)
  (displayln "RETENTION-CENSUS modules=" size
    " expansions=" body-expansions " live-bytes=" (.get memory live-bytes)
    " reader-roots=" retention)
  (report-reader-contexts size prior-contexts)
  (check-equal? (object? (hash-get lifetime 'publication)) #t)
  (hash-put! lifetime 'graph graph)
  (hash-put! lifetime 'namespace (.get fixture modules))
  (when earlier
    ;; Measure the OLD+NEW identity union, not two sums with duplicated language
    ;; support. Old sources have been removed: this is liveness, never admission.
    ;; Actual issuer records come from existing caches; do not rebuild a bundle.
    (let ()
      (def (root cohort)
        (let* ((source (hash-get cohort 'source))
               (reads (and (object? source) (object-%reads source))))
          (and reads (hash-get reads 'selected-graph))))
      (def current (root lifetime))
      (def prior (root earlier))
      (check-equal? (and current prior #t) #t)
      (check-equal? (eq? current prior) #f)
      (report-retained-reads (list size 'current-source-root) (read-identities (list current)))
      (report-retained-reads (list size 'with-prior-source-root) (read-identities (list current prior)))))
  lifetime)
(.def (CensusProfile @ ModuleTestingProfile.) emit?: #t trace-enabled?: #f)
(def module-retention-census-test
  (let ((earlier #f) (earlier-root #f))
    (test-suite "Bounded retained runtime read attribution through real init"
      (yuanxu-test-fixture "sixteen real modules"
        profile: CensusProfile (fixture (.cc DeclarationFixture size: 16))
        ;; A path string owns no receiver/Graph; all object witnesses stay weak.
        (set! earlier-root (string-copy (.get fixture root)))
        (set! earlier (census fixture 16)))
      (yuanxu-test-fixture "thirty-two real modules"
        profile: CensusProfile (fixture (.cc DeclarationFixture size: 32))
        ;; No previous resource, receiver or read escapes through this table.
        ;; Collection here is outside the 32 cold window and is reported as a
        ;; separate diagnostic regime, not a comparable before/after speedup.
        (##gc) (##gc)
        (displayln "RETENTION-RELEASED-COHORT modules=16 graph-live="
          (and (hash-get earlier 'graph) #t) " publication-live="
          (and (hash-get earlier 'publication) #t)
          " namespace-live=" (and (hash-get earlier 'namespace) #t)
          " selection-cached-graph="
          (let* ((source (hash-get earlier 'source))
                 (fields (and source (object-%instance source))))
            (and fields (hash-get earlier 'graph)
              (eq? (hash-get earlier 'graph) (hash-get fields 'selected-graph)))))
        ;; Runtime import liveness does not approve deleted source. Refusing the
        ;; old entry must not poison the next independent entry's admission.
        (check-exception ((.get (hash-get earlier 'graph) admit-current))
          (lambda (failure)
            (and (Error? failure)
                 (equal? (Error-message failure) "module role must be a regular file")
                 (pair? (Error-irritants failure))
                 (string? (car (Error-irritants failure)))
                 (string-prefix? (string-append earlier-root "/modules/")
                                 (car (Error-irritants failure)))
                 (string-suffix? "/types.ss" (car (Error-irritants failure))))))
        (census fixture 32 earlier)))))
