;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module-specific adapter of the existing Case policy, never a runner.
(import :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-default-testing-case-profile
                 yuanxu-test-checkpoint yuanxu-test-observe)
        (only-in :yuanxu/observability/memory yuanxu-debug-cpu-microseconds)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 current-module-process-trace-budget))
(export ModuleTestingProfile.)

;; Stable owner/role labels distinguish many modules' func.ss and types.ss.
;; This is only formatting of an observed path: no scan, import or slot read.
(def observation-source-root
  ;; Diagnostic labels only need lexical parent directories. A compiled
  ;; module may outlive its source sandbox; formatting must not stat or reopen
  ;; that deleted tree, and cannot authenticate any observed source.
  (let* ((building (path-directory (this-source-file)))
         (module-system
           (path-directory (path-strip-trailing-directory-separator building))))
    (path-directory (path-strip-trailing-directory-separator module-system))))
(def (source-label path)
  (if (string-prefix? observation-source-root path)
    (substring path (string-length observation-source-root) (string-length path))
    (path-strip-directory path)))

(def (module-test-observer previous trace?)
  ;; Report completed work through the existing scalar Ops channel. Merely
  ;; printing a diagnostic line is not progress for its supervising process.
  ;; No checkpoint receipt/POO construction is permitted inside admission.
  (def progress-scope (gensym 'module-completed-work))
  (def completed-work 0)
  (def started (current-jiffy))
  (def started-cpu (yuanxu-debug-cpu-microseconds))
  ;; Diagnostic counts only: bounded owner/phase rows, never source bytes,
  ;; SDK contexts or currentness results. This cannot authorize reuse.
  (def read-rows (and trace? (make-hash-table)))
  (def effect-reads (make-hash-table))
  (def graph-read-rows (make-hash-table))
  (def effect-checks (make-hash-table))
  (def physical-reads 0)
  (def public-requests 0)
  (def public-preparations 0)
  (def kernel-requests 0)
  (def kernel-walks 0)
  (def kernel-visits 0)
  (def effects '())
  (def guard-origins '())
  (def publications 0)
  (def replay-visits 0)
  (def (span-total key (cpu? #f))
    (let (span (find (lambda (span) (eq? key (caddr (vector-ref span 0)))) spans))
      (if span (vector-ref span (if cpu? 5 4)) 0)))
  (def (report-phase-work (force? #f))
    ;; Bounded checkpoints survive a later outer TERM without retaining a
    ;; token/context census or waiting for a successful Case's final receipt.
    (when (and trace? (or force? (zero? (modulo publications 64))))
      (yuanxu-write-observation-line!
        "reader-phase-wall publications=%s import-us=%s compile-us=%s eval-us=%s replay-us=%s replay-visits=%s guard-us=%s"
        publications (span-total 'import-microseconds)
        (span-total 'reader-compile-microseconds)
        (span-total 'reader-eval-microseconds)
        (span-total 'metadata-replay-microseconds)
        replay-visits
        (span-total 'source-guard-microseconds))
      (yuanxu-write-observation-line!
        "reader-phase-cpu publications=%s import-us=%s compile-us=%s eval-us=%s replay-us=%s guard-us=%s"
        publications (span-total 'import-microseconds #t)
        (span-total 'reader-compile-microseconds #t)
        (span-total 'reader-eval-microseconds #t)
        (span-total 'metadata-replay-microseconds #t)
        (span-total 'source-guard-microseconds #t))
      (for-each
        (lambda (keys)
          (yuanxu-write-observation-line!
            "reader-boundary publications=%s kind=%s wall-us=%s cpu-us=%s"
            publications (car keys) (span-total (cadr keys))
            (span-total (cadr keys) #t)))
        '((location reader-location-microseconds reader-location-cpu-microseconds)
          (preparation reader-preparation-microseconds reader-preparation-cpu-microseconds)
          (interface reader-interface-microseconds reader-interface-cpu-microseconds)
          (admission reader-admission-microseconds reader-admission-cpu-microseconds)
          (projection reader-projection-microseconds reader-projection-cpu-microseconds)))))
  (def (read-owner path)
    (let (parts (string-split (source-label path) #\/))
      (cond
        ((string-contains path "/clan/poo/") "gerbil-poo")
        ((and (member (car parts) '("modules" "module-system" "scenarios" "t"))
              (pair? (cdr parts)))
         (string-append (car parts) "/" (cadr parts)))
        (else (car parts)))))
  (def (record-read phase path amount)
    (set! physical-reads (+ physical-reads amount))
      (let* ((effect (if (pair? effects) (car effects) '(outside-effect . source)))
             (key (if (or (hash-key? effect-reads effect) (< (hash-length effect-reads) 128))
                    effect '(overflow . other))))
        (hash-put! effect-reads key (+ amount (or (hash-get effect-reads key) 0))))
    (when (and (pair? effects)
               (equal? (car effects) '(admission-stage-start . build-graph)))
      (let* ((row (cons phase (if (pair? guard-origins) (car guard-origins) 'outside-guard)))
             (key (if (or (hash-key? graph-read-rows row)
                          (< (hash-length graph-read-rows) 128))
                    row '(overflow . other))))
        (hash-put! graph-read-rows key (+ amount (or (hash-get graph-read-rows key) 0)))))
    (when read-rows
      (let* ((row (list phase (if (pair? guard-origins) (car guard-origins) 'outside-guard)
                        (read-owner path)))
             (key (if (or (hash-key? read-rows row) (< (hash-length read-rows) 1024))
                    row '(overflow outside-guard "other"))))
        (hash-put! read-rows key (+ amount (or (hash-get read-rows key) 0))))))
  (def (flush-reads)
    (report-phase-work #t)
    (hash-for-each
      (lambda (key amount)
        (yuanxu-write-observation-line!
          "graph-source phase=%s guard=%s reads=%s" (car key) (cdr key) amount))
      graph-read-rows)
    (when trace?
      (yuanxu-write-observation-line!
        "public-source-preparation requests=%s preparations=%s"
        public-requests public-preparations)
      (yuanxu-write-observation-line!
        "kernel-source-closure requests=%s walks=%s visits=%s"
        kernel-requests kernel-walks kernel-visits))
    (when read-rows
      (for-each
        (lambda (row)
          (yuanxu-write-observation-line!
            "source-physical phase=%s boundary=%s owner=%s reads=%s"
            (caar row) (cadar row) (caddar row) (cdr row)))
        (hash->list read-rows)))
    (when effect-reads
      (for-each
        (lambda (row)
          (yuanxu-write-observation-line! "source-effect kind=%s boundary=%s reads=%s"
            (caar row) (cdar row) (cdr row)))
        (hash->list effect-reads)))
    (hash-for-each
      (lambda (key microseconds)
        (yuanxu-write-observation-line! "source-effect-check kind=%s boundary=%s microseconds=%s"
          (car key) (cdr key) microseconds)) effect-checks))
  ;; Closed categories, not a path/context registry. Nested imports/guards are
  ;; counted as a union of spans so recursive import edges do not multiply time.
  ;; Keep timing scalar even when this observer runs inside domain admission.
  (def spans
    (map (lambda (keys) (vector keys 0 0 0 0 0))
      '((native-source-import-start native-source-import-end
          import-microseconds import-cpu-microseconds)
        (publication-start publication-end
          publication-microseconds publication-cpu-microseconds)
        (publication-guard-start publication-guard-end
          source-guard-microseconds source-guard-cpu-microseconds)
        (metadata-replay-start metadata-replay-end
          metadata-replay-microseconds metadata-replay-cpu-microseconds)
        (reader-compile-start reader-compile-end
          reader-compile-microseconds reader-compile-cpu-microseconds)
        (reader-eval-start reader-eval-end
          reader-eval-microseconds reader-eval-cpu-microseconds)
        (reader-location-start reader-location-end
          reader-location-microseconds reader-location-cpu-microseconds)
        (reader-preparation-start reader-preparation-end
          reader-preparation-microseconds reader-preparation-cpu-microseconds)
        (reader-interface-start reader-interface-end
          reader-interface-microseconds reader-interface-cpu-microseconds)
        (reader-admission-start reader-admission-end
          reader-admission-microseconds reader-admission-cpu-microseconds)
        (reader-projection-start reader-projection-end
          reader-projection-microseconds reader-projection-cpu-microseconds)
        (package-process-start package-process-end
          package-microseconds package-cpu-microseconds))))
  (def (observe-span category)
    (for-each
      (lambda (span)
        (let ((keys (vector-ref span 0)) (depth (vector-ref span 1)))
          (cond
            ((eq? category (car keys))
             (when (zero? depth)
               (vector-set! span 2 (current-jiffy))
               (vector-set! span 3 (yuanxu-debug-cpu-microseconds)))
             (vector-set! span 1 (+ depth 1)))
            ((and (eq? category (cadr keys)) (> depth 0))
             (vector-set! span 1 (- depth 1))
             (when (= depth 1)
               (let ((wall (quotient (* (- (current-jiffy) (vector-ref span 2)) 1000000)
                                     (jiffies-per-second)))
                     (cpu (- (yuanxu-debug-cpu-microseconds) (vector-ref span 3))))
                 (vector-set! span 4 (+ wall (vector-ref span 4)))
                 (vector-set! span 5 (+ cpu (vector-ref span 5)))
                 ;; Internal diagnostic spans must not consume the Case's
                 ;; unchanged 64 DOMAIN-category allowance.
                 (when (memq (car keys) '(native-source-import-start publication-start
                                         publication-guard-start package-process-start))
                   (yuanxu-test-observe (caddr keys) wall)
                   (yuanxu-test-observe (cadddr keys) cpu))))))))
      spans))
  ;; Automatic events can occur INSIDE domain admission. Do not construct or
  ;; inspect telemetry POO objects there: their reads would enter its MOP
  ;; dependency graph. The Case watchdog still samples/enforces memory, and
  ;; explicit author checkpoints retain their full receipt API.
  (def (stage category name (force? #f))
    (when (or trace? force?)
      (yuanxu-write-observation-line!
        "test-stage %s/%s elapsed-ms=%s cpu-ms=%s source-reads=%s" category name
        (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second))
        (quotient (- (yuanxu-debug-cpu-microseconds) started-cpu) 1000)
        physical-reads)))
  (def (observe key amount)
    ;; Never retain SDK objects in compound discovery keys. Only their closed
    ;; event category contributes a counter; actual objects stay with the SDK.
    (let (category (if (pair? key) (car key) key))
      (when (symbol? category)
        (cond
          ((eq? category 'metadata-replay-visits)
           (set! replay-visits (+ replay-visits amount)))
          ((memq category '(metadata-replay-start metadata-replay-end
                            reader-compile-start reader-compile-end reader-eval-start reader-eval-end
                            reader-location-start reader-location-end
                            reader-preparation-start reader-preparation-end
                            reader-interface-start reader-interface-end
                            reader-admission-start reader-admission-end
                            reader-projection-start reader-projection-end))
           (void))
          ;; Fixed diagnostic scalars must not displace the Case's domain
          ;; work categories. The original observer still receives each event.
          ((memq category '(public-preparation-requests public-preparation-walks
                            kernel-closure-requests kernel-closure-walks kernel-context-visits
                            reader-binding-roots reader-read-roots compiler-enrollment))
           (unless (and (exact-integer? amount) (>= amount 0))
             (error "source preparation observation requires a natural count"))
           (case category
             ((public-preparation-requests) (set! public-requests (+ public-requests amount)))
             ((public-preparation-walks) (set! public-preparations (+ public-preparations amount)))
             ((kernel-closure-requests) (set! kernel-requests (+ kernel-requests amount)))
             ((kernel-closure-walks) (set! kernel-walks (+ kernel-walks amount)))
             ((kernel-context-visits) (set! kernel-visits (+ kernel-visits amount)))))
          ((eq? category 'check-seconds)
            (unless (and (real? amount) (<= 0 amount) (< amount +inf.0))
              (error "source check duration must be finite and nonnegative"))
            (yuanxu-test-observe 'check-microseconds
              (inexact->exact (round (* amount 1000000))))
            (let* ((effect (if (pair? effects) (car effects) '(outside-effect . source)))
                   (key (if (or (hash-key? effect-checks effect) (< (hash-length effect-checks) 128))
                          effect '(overflow . other))))
              (hash-update! effect-checks key
                (cut + <> (inexact->exact (round (* amount 1000000)))) 0)))
          (else (yuanxu-test-observe category amount))))
      (when (pair? key)
        ;; Scalar snapshots distinguish one cold Graph demand from subsequent
        ;; native cache hits. Never probe a cold receiver merely to label it.
        (when (and (memq category '(admission-stage-start admission-stage-end))
                   (memq (cadr key) '(build-graph artifact-publication-current)))
          (stage category (cadr key) #t))
        ;; Innermost active effect brackets partition physical reads without
        ;; summing overlapping spans. Names are producer-owned scalar labels.
        (begin
          (case category
            ((package-stage-start admission-stage-start link-stage-start package-process-start native-source-import-start)
             (set! effects
               (cons (cons category
                       (if (eq? category 'native-source-import-start)
                         (read-owner (cadr key)) (cadr key))) effects)))
            ((package-stage-end admission-stage-end link-stage-end package-process-end native-source-import-end)
             (when (pair? effects) (set! effects (cdr effects))))))
        (when (memq category '(native-source-import-start native-source-import-end
                              publication-start publication-end
                              publication-guard-start publication-guard-end
                              metadata-replay-start metadata-replay-end
                              reader-compile-start reader-compile-end
                              reader-eval-start reader-eval-end
                              reader-location-start reader-location-end
                              reader-preparation-start reader-preparation-end
                              reader-interface-start reader-interface-end
                              reader-admission-start reader-admission-end
                              reader-projection-start reader-projection-end
                              package-process-start package-process-end))
          (observe-span category))
        (case category
          ((file-read)
           (record-read (cadr key) (caddr key) amount))
          ((publication-guard-start)
           (set! guard-origins (cons (cadr key) guard-origins))
           (stage category (cadr key)))
          ((publication-guard-end)
           (stage category (cadr key))
           (when (pair? guard-origins) (set! guard-origins (cdr guard-origins))))
          ((publication-start publication-end)
           (when (eq? category 'publication-end)
             (set! publications (+ publications 1))
             (report-phase-work))
           (stage category
             (path-strip-directory
               (path-strip-trailing-directory-separator (path-directory (cadr key))))))
          ((package-stage-start package-stage-end admission-stage-start admission-stage-end
            package-process-start package-process-end)
           (stage category (cadr key)))
          ((package-store-validity)
           (stage category (cadr key)))
          ((native-source-import-start native-source-import-end)
           (stage category (source-label (cadr key))))
          ((reader-retention reader-binding-roots reader-read-roots reader-lifetime reader-declaration package-process-observation)
           ;; Producers own these closed scalar rows; reject unexpected payloads
           ;; rather than print syntax or accidentally root a runtime object.
           (unless (and (list? (cdr key))
                        (andmap (lambda (row)
                                  (and (pair? row) (symbol? (car row))
                                       (exact-integer? (cdr row)) (>= (cdr row) 0)))
                                (cdr key)))
             (error "module test observation requires scalar fields" category))
           (when trace? (yuanxu-write-observation-line! "%s %s" category (cdr key)))
           (when (eq? category 'package-process-observation)
             (for-each (lambda (row) (yuanxu-test-observe (car row) (cdr row))) (cdr key)))
           (when (eq? category 'reader-declaration)
             (stage category 'body)))))
      (when previous (previous key amount))
      (when (and (memq category '(reader-body-compiled reader-body-evaluated
                                  publication-guard-end metadata-replay-visits))
                 (exact-integer? amount) (> amount 0))
        (set! completed-work (+ completed-work amount))
        (execution-progress! progress-scope completed-work))))
  (values observe flush-reads))

;; Retain only the native function binding. Tracing still executes afresh in
;; each Case, with its own weak identities, observer scope and cleanup.
(def retention-observer
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core))
      (eval-syntax '(import (only-in :yuanxu/module-system/building/test-retention observe-read-dependencies)))
      (eval-syntax 'observe-read-dependencies))))

(def (observe-module-test run)
  (lambda (self description thunk)
    (if (.get self emit?)
      (let (trace? (.get self trace-enabled?))
        (defvalues (observer flush-reads)
          (module-test-observer (current-module-source-observer) trace?))
        (parameterize ((current-module-source-observer
                         observer)
                       ;; The first four calls cover construction's evaluation,
                       ;; store lookup, realization and first currentness check.
                       ;; No evaluator/debug dump for every repeated admission.
                       (current-module-process-trace-budget (and trace? (box 4))))
          (dynamic-wind void
            (lambda ()
              (run self description
                (if trace? (lambda () ((force retention-observer) thunk)) thunk)))
            flush-reads)))
      (run self description thunk))))


(.def (ModuleTestingProfile. @ yuanxu-default-testing-case-profile)
  trace-enabled?: #f
  (.run => observe-module-test))
