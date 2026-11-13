;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source observation, replay and currentness share one runtime owner.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-observation %slot-read-active? without-observation)
        (only-in :std/list/list any take)
        (only-in :gerbil/expander call-with-input-source-file source-file-settings)
        (only-in :std/misc/ports read-all-as-string read-all-as-u8vector))
(export observe-source
        module-source-type module-source-read module-source-name? module-source-admit-current!
        module-source-text-guard
        module-compiler-interface-source
        call-with-module-source-read-cache call-with-module-source-fresh-reads
        call-with-module-source-callback module-source-window-preserved?
        call-with-collected-module-sources
        module-source-observe current-module-source-observer current-module-source-phase
        current-module-process-trace-budget
        call-with-module-source-operation-measurement module-source-measure-operation module-source-measure-replay
        module-source-checked-operation module-source-operation-procedure
        module-source-operation-resume module-source-object-policy module-source-object-policies)

;; Read-only runtime identity/revision support for parser-owned metadata. This
;; is not a currentness-result cache: every call compares the actual revisions
;; of every captured receiver/ancestor. Closed metadata rejects MOP;
;; a general source identity snapshot can preserve an existing opaque protocol
;; without certifying its execution as pure.
(def (module-source-object-policy roots reject-protocols?: (reject-protocols? #t))
  (def seen (make-hash-table-eq))
  (def entries '())
  (def (visit value)
    (unless (hash-key? seen value)
      (hash-put! seen value #t)
      (set! entries (cons (cons value (object-revision value)) entries))
      (for-each visit (object-supers value))))
  (for-each visit roots)
  (source-object-policy entries reject-protocols?))
(def (module-source-object-policies groups)
  ;; One capture serves the complete policy and the separate group policies.
  ;; Only revision records survive. Every invocation checks the live objects.
  (def captured (make-hash-table-eq))
  (def complete '())
  (def (capture value)
    (or (hash-get captured value)
        (let* ((entry (cons value (object-revision value)))
               (record (cons entry (object-supers value))))
          (hash-put! captured value record)
          (set! complete (cons entry complete))
          record)))
  (def (group-policy roots)
    (def seen (make-hash-table-eq))
    (def entries '())
    (def (visit value)
      (unless (hash-key? seen value)
        (hash-put! seen value #t)
        (let (record (capture value))
          (set! entries (cons (car record) entries))
          (for-each visit (cdr record)))))
    (for-each visit roots)
    (source-object-policy entries #t))
  (def policies (map group-policy groups))
  (values (source-object-policy complete #t) policies))
(def (source-object-policy entries reject-protocols?)
  ;; Construct outside the capture frame; do not retain its traversal table.
  (lambda ()
    (andmap (lambda (entry)
              (and (= (cdr entry) (object-revision (car entry)))
                   (or (not reject-protocols?)
                       ;; Every ancestor is already in entries. Inspect its
                       ;; actual protocol field without forcing a cold C4 cache.
                       (not (object-%protocol (car entry)))))) entries)))

;; Structural decomposition of ONE operation, not a source approval or cache.
;; Only this constructor creates the paired entry/resume procedures. Neither
;; procedure retains a check result; every invocation still runs the tail guard.
(defstruct source-checked-operation (guard invoke resume) final: #t)
(def (module-source-checked-operation guard action)
  (unless (and (procedure? guard) (procedure? action))
    (error "source operation requires a guard and an action"))
  (def (resume) (action) (guard))
  (make-source-checked-operation guard (lambda () (guard) (resume)) resume))
(def (module-source-operation-procedure operation)
  (source-checked-operation-invoke operation))
(def (module-source-operation-resume receiver guard)
  ;; Inspect ONLY an already prepared ordinary runtime receiver, without a MOP
  ;; hook or read observer. Cold/mutated objects, overridden methods, different
  ;; guards and instrumented reads retain the ordinary checked call. This probe
  ;; must not execute anything between the caller's guard and the continuation.
  (and (object? receiver) (object-%instance receiver)
       (not (%slot-read-active?)) (not (object-protocol receiver))
       (let ((operation (.ref/cached receiver '%source-operation (lambda () #f)))
             (invoke (.ref/cached receiver 'admit-current (lambda () #f))))
         (and (source-checked-operation? operation)
              (eq? guard (source-checked-operation-guard operation))
              (eq? invoke (source-checked-operation-invoke operation))
              (source-checked-operation-resume operation)))))

(def (module-source-name? name)
  (and (string? name) (> (string-length name) 0)
       (not (member name '("." "..")))
       (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list name))))

(def current-module-source-observer (make-parameter #f))
;; Invocation-local diagnostics only. Unlike a source observer, enabling this
;; timer does not turn on read observation or alter its runtime fast paths.
(def current-module-source-operation-times (make-parameter #f))
(def current-module-source-operation-accounting? (make-parameter #t))
(def (call-with-module-source-operation-measurement action accounting?: (accounting? #t))
  ;; The runtime scalar table is private for the entire action. Report it only
  ;; afterwards: callers cannot install a custom hash/ref callback in the
  ;; middle of the reader's otherwise closed runtime replay segment.
  (unless (memq accounting? '(#t #f stages))
    (error "expected Boolean or stages operation accounting mode"))
  (let (times (make-hash-table))
    (def value (parameterize ((current-module-source-operation-times times)
                             (current-module-source-operation-accounting? accounting?)) (action)))
    (values value times)))
(def (module-source-measure-operation name action)
  (let (times (current-module-source-operation-times))
    (if (not times) (action)
      (let* ((initialization
               (and (pair? name)
                    (memq (car name) '(reader-initialization reader-initializer-body))
                    (car name)))
             (accounting (current-module-source-operation-accounting?)))
        (if (and initialization (not accounting)) (action)
          ;; Stage summaries retain only initializer families. Explicit detailed
          ;; accounting keeps source paths. Owner-qualified scope counters
          ;; retain their identities in every mode.
          (let (name (if (and initialization (eq? accounting 'stages)) initialization name))
            (hash-update! times (list 'calls name) (cut + <> 1) 0)
            ;; Attribute bounded stages, not each leaf read/query. In particular
            ;; source-read starts AFTER its read-attempt counter was incremented.
            (if (or (and (pair? name) (eq? (car name) 'reader-current))
                    (memq name '(build-main build-selected-graph std-make reader-bootstrap
                            reader-current reader-interface-start reader-preparation-start
                            reader-admission-start reader-native-import reader-role-import
                            reader-tool-inputs reader-private-closure reader-compile-start
                            reader-eval-start metadata-replay source-init-current
                            compiler-input-lookup compiler-role-inventory
                            compiler-import-before compiler-import-after
                            compiler-view-before compiler-view-after)))
              (measure-source-read-attempts times name
                (lambda () (measure-source-operation times name action)))
              (measure-source-operation times name action))))))))
(def (measure-source-operation times name action)
  (if (if (eq? (current-module-source-operation-accounting?) 'stages)
              (or (and (pair? name)
                       (memq (car name) '(reader-initialization reader-initializer-body
                                         reader-candidate-replay-site)))
                  (memq name '(reader-initialization reader-initializer-body
                           build-main build-specification build-dispatch std-make build-current
                           profile-interface-scan reader-bootstrap reader-preparation-start reader-interface-start
                           selected-owner-closure selected-core-projection selected-topological-resolution
                           reader-wrapper-write reader-wrapper-expansion reader-interface-read reader-interface-rewrite
                           reader-admission-start reader-value-admission reader-admission-evidence
                           reader-current metadata-replay reader-candidate-fused-return-replay
                           metadata-index metadata-root-merge metadata-cache-miss-receivers
                           source-init-current source-authoring-profile-checkpoint
                           reader-tool-inputs reader-private-closure reader-private-prepare
                           reader-native-import reader-role-import reader-source-resolution
                           reader-compile-start reader-eval-start
                           reader-expander-compile reader-expander-eval
                           reader-expander-phase-compile reader-expander-phase-eval
                           source-authoring source-authoring-profile source-authoring-role
                           source-direction source-import-policy source-parse)))
              (and (current-module-source-operation-accounting?)
                 (memq name '(metadata-replay selection-current selected-graph reader-current source-read
                        selected-owner-closure selected-core-projection selected-topological-resolution
                        build-projection build-current std-make
                        build-product-repair build-product-require))))
          (measure-source-accounting times name action)
          (let (started (real-time))
            (dynamic-wind void action
              (lambda ()
                (hash-update! times name (cut + <> (- (real-time) started)) 0))))))
(def (measure-source-read-attempts times name action)
  ;; Inclusive scalar attribution in the SAME private diagnostic table. No
  ;; source observer, source-read window or approval is installed. Nested spans
  ;; overlap; never sum them as disjoint filesystem work. Failed I/O attempts
  ;; remain attempts, not successfully admitted byte observations.
  (def before (hash-ref times '(source reads) 0))
  (def init-characters
    (and (eq? name 'source-init-current)
         (hash-ref times '(characters source-read) 0)))
  (dynamic-wind void action
    (lambda ()
      (hash-update! times (list 'read-attempts name)
        (cut + <> (- (hash-ref times '(source reads) 0) before)) 0)
      (when init-characters
        (hash-update! times '(characters source-init-current)
          (cut + <> (- (hash-ref times '(characters source-read) 0) init-characters)) 0)))))
(def (measure-source-accounting times name action)
  ;; Use installed Gambit's own sample/frame correction, not duplicated vector
  ;; indices. The signed VM account is NOT physical constructor allocation.
  (def failed? #f)
  (def failure #f)
  (def stats
    (##exec-stats
      (lambda ()
        (with-catch
          (lambda (exception) (set! failed? #t) (set! failure exception) '())
          (lambda () (call-with-values action list))))))
  (def (metric key) (cdr (assq key stats)))
  (hash-update! times name (cut + <> (metric 'real-time)) 0)
  (for-each
    (lambda (entry)
      (hash-update! times (list (car entry) name) (cut + <> (metric (cdr entry))) 0))
    '((cpu-user . user-time) (cpu-system . sys-time)
      (gc-user . gc-user-time) (gc-system . gc-sys-time) (gc-wall . gc-real-time)
      (collections . nb-gcs) (minor-faults . minflt) (major-faults . majflt)
      (vm-account . bytes-allocated)))
  (hash-update! times (list 'wall-cpu-gap name)
    (cut + <> (- (metric 'real-time) (+ (metric 'user-time) (metric 'sys-time)))) 0)
  (when (< (metric 'bytes-allocated) 0)
    (hash-update! times (list 'accounting-invalid name) (cut + <> 1) 0))
  (if failed? (raise failure) (apply values (metric 'result))))
;; Fixed results use the native validation-only path. Keep actual checkpoint
;; work inside the issuer's protected frame.
(def (module-source-measure-replay reads (checkpoint #f))
  (let (times (current-module-source-operation-times))
    (if (or times checkpoint)
      (module-source-measure-operation 'metadata-replay
        (lambda ()
          (def (record-visits! visits)
            (when times
              (hash-update! times '(visits metadata-replay) (cut + <> visits) 0)))
          (if checkpoint
            (call-with-current-slot-reads reads
              (lambda (visits)
                (record-visits! visits)
                (module-source-measure-operation 'metadata-checkpoints checkpoint)))
            (begin
              (record-visits! (call-with-current-slot-reads reads values))
              (void)))))
      (call-with-current-slot-reads reads void))))
;; A Case-owned logging allowance, never a query/currentness cache. The testing
;; adapter binds a fresh box only for detailed observation; execution consumes
;; it solely to add the provider's diagnostic flags to a bounded set of calls.
(def current-module-process-trace-budget (make-parameter #f))
;; Observer keys remain numeric counters: symbols for totals, or
;; (file-request/file-read phase path) for attribution. No observer, no path keys.
(def current-module-source-phase (make-parameter 'source))
(def (observe-source kind (amount 1))
  (when (and (symbol? kind) (current-module-source-operation-times))
    (hash-update! (current-module-source-operation-times) (list 'source kind)
      (cut + <> amount) 0))
  (when (current-module-source-observer)
    ((current-module-source-observer) kind amount)))
(def (module-source-type path)
  (module-source-observe read-module-source-type path))
(def (read-module-source-type path)
  (observe-source 'stats)
  ;; Absence is data; an I/O/type failure is not an absent source and must not
  ;; become a cached #f or a misleading stale-input diagnostic. Match the
  ;; existing role discovery boundary and preserve the original exception.
  (with-catch
    (lambda (exception)
      (if (no-such-file-or-directory-exception? exception) #f (raise exception)))
    (lambda () (file-info-type (file-info path #f)))))
;; A reader validation is synchronous and effect-free. Reuse bytes and file-kind
;; observations only inside that boundary; every read requires regular-file
;; status. No cache survives an effect or an independent currentness call.
(def source-read-cache (make-parameter #f))
(def (module-source-window-preserved? action)
  (let (window (source-read-cache))
    (action)
    (and window (eq? window (source-read-cache)))))
;; A private absence identity; #f is a valid cached observation. This is only
;; the existing runtime table's default value, not another cache or verdict.
(def missing-source-query (gensym 'missing-source-query))
;; Pure-query reuse must also preserve enrollment in an enclosing admission.
;; Each nested collector is a distinct demand even when bytes are unchanged.
(def source-collectors (make-parameter '()))
(def (call-with-module-source-fresh-reads thunk)
  ;; Admission is an authority boundary even when a caller has an outer pure
  ;; observation window. Restore that window afterwards; never inherit its bytes.
  (parameterize ((source-read-cache #f)) (thunk)))
(def (call-with-module-source-callback thunk)
  ;; Native void has no callback body. Every other procedure is an effect
  ;; boundary, not a purity claim inferred from a warm object or procedure name.
  (if (eq? thunk void) (thunk)
    (let (enclosing (source-read-cache))
      (def (clear!)
        (when enclosing
          (hash-clear! enclosing)
          ;; Opaque code can replace a previously closed guard or observer.
          ;; Do not resume the closed-prefix assumption after that callback.
          (source-read-cache #f)))
      ;; Invalidate the EXISTING window on both entry and resumption, including
      ;; unwinding/reentry. Merely suspending it restores stale observations
      ;; after an author callback. Cleanup never replaces the callback's error.
      (dynamic-wind clear!
        (lambda () (call-with-module-source-fresh-reads thunk)) clear!))))
(def (call-with-module-source-read-cache thunk)
  (observe-source 'checks)
  ;; Requests include nested guards. Count actual fresh observation windows
  ;; separately so attribution cannot mistake cache hits for filesystem passes.
  (unless (source-read-cache) (observe-source 'read-windows))
  ;; Nested pure source guards share the outer validation's observations. The
  ;; owner MUST end this scope before expansion, writes or external effects.
  (cond
   ((source-read-cache) (thunk))
   ((not (current-module-source-observer))
    (parameterize ((source-read-cache (make-hash-table))) (thunk)))
   (else
    (let (started (real-time))
      (dynamic-wind void
        (lambda () (parameterize ((source-read-cache (make-hash-table))) (thunk)))
        (lambda () (observe-source 'check-seconds (- (real-time) started))))))))
(def (module-source-observe query . arguments)
  ;; Pure observations only, within the same validation boundary as file bytes.
  (let (cache (source-read-cache))
    (if cache
      ;; File-kind lookup has no collector enrollment. Share that physical
      ;; query across collectors in this same pure window; byte guards and
      ;; arbitrary queries still rerun for each collector and enroll normally.
      (let (key (cons query (cons (if (eq? query read-module-source-type)
                                   '() (source-collectors)) arguments)))
        (if (current-module-source-observer)
          ;; Open observers retain the original lookup/callback order. They
          ;; may mutate an argument or exit while reporting a cache hit.
          (if (hash-key? cache key)
            (begin (observe-source 'query-hits) (hash-ref cache key))
            (let (value (apply query arguments))
              (observe-source 'query-misses)
              (hash-put! cache key value) value))
          (let (value (hash-ref cache key missing-source-query))
            (if (eq? value missing-source-query)
              (let (value (apply query arguments))
                (observe-source 'query-misses)
                (hash-put! cache key value) value)
              (begin (observe-source 'query-hits) value)))))
      (apply query arguments))))
(def (observe-read-request path)
  (observe-source 'read-requests)
  (when (current-module-source-observer)
    (observe-source (list 'file-request (current-module-source-phase) path))))
(def (observe-read path)
  (observe-source 'reads)
  (when (current-module-source-observer)
    (observe-source (list 'file-read (current-module-source-phase) path))))
(def (record-physical-source-read! characters)
  (let (times (current-module-source-operation-times))
    (when times
      (hash-update! times '(characters source-read) (cut + <> characters) 0)
      (hash-update! times (list 'physical-reads (current-module-source-phase)) (cut + <> 1) 0)
      (hash-update! times (list 'source-characters (current-module-source-phase))
        (cut + <> characters) 0))))
;; A matched large read already has an exact private text snapshot. Expose a
;; mutable copy only when an ordinary reader asks for the text in this window.
(defstruct source-text-read (snapshot materialized) final: #t)
(defstruct source-text-snapshot (text chunks) final: #t)
(def current-source-text-snapshot (make-parameter #f))
(def (source-text-content text)
  (if (source-text-read? text)
    (or (source-text-read-materialized text) (source-text-read-snapshot text))
    text))
(def (materialize-source-text text)
  (if (source-text-read? text)
    (or (source-text-read-materialized text)
        (let (copy (string-copy (source-text-read-snapshot text)))
          (set! (source-text-read-materialized text) copy)
          copy))
    text))
(def (module-source-read path)
  (read-module-source path #f))
(def (read-module-source path expected-length)
  (observe-read-request path)
  (unless (eq? (module-source-type path) 'regular)
    (error "module role must be a regular file" path))
  (read-regular-source path expected-length))
(def (scheme-source-path? path)
  (equal? (path-extension path) ".ss"))
(def source-read-chunk-size 8192)
(def (source-text->snapshot text)
  (def snapshot (string-copy text))
  (def bytes (string->utf8 snapshot))
  (def size (u8vector-length bytes))
  (make-source-text-snapshot snapshot
    (let loop ((start 0))
      (if (= start size) '()
        (let (end (min (+ start source-read-chunk-size) size))
          (cons (subu8vector bytes start end) (loop end)))))))
(def (decode-source-bytes bytes)
  (def port (open-input-u8vector (cons* init: bytes source-file-settings)))
  (dynamic-wind void
    (lambda ()
      (call-with-output-string
        (lambda (out)
          (def buffer (make-string source-read-chunk-size))
          (let loop ()
            (let (count (read-substring buffer 0 source-read-chunk-size port))
              (unless (zero? count)
                (write-substring buffer 0 count out)
                (loop)))))))
    (lambda () (close-input-port port))))
(def (read-source-snapshot path snapshot)
  ;; Gerbil owns the decoding settings. A canonical byte match already
  ;; proves the decoded text. Otherwise decode the bytes from this same
  ;; open file, including the matched prefix and the rest through EOF.
  (call-with-input-source-file path
    (lambda (port)
      (def expected (source-text-snapshot-chunks snapshot))
      (def buffer (make-u8vector source-read-chunk-size))
      (def (decode-change matched tail)
        (decode-source-bytes
          (u8vector-concatenate
            (append (take expected matched) (list tail (read-all-as-u8vector port))))))
      (let loop ((chunks expected) (matched 0))
        (if (null? chunks)
          (let (next (read-u8 port))
            (if (eof-object? next)
              (make-source-text-read (source-text-snapshot-text snapshot) #f)
              (decode-change matched (u8vector next))))
          (let* ((chunk (car chunks))
                 (size (u8vector-length chunk))
                 (target (if (= size source-read-chunk-size) buffer (make-u8vector size)))
                 (count (read-subu8vector target 0 size port)))
            (if (and (= count size) (equal? target chunk))
              (loop (cdr chunks) (1+ matched))
              (begin
                (u8vector-shrink! target count)
                (decode-change matched target)))))))))
(def (read-source-text path expected-length)
  (let (snapshot (and expected-length (current-source-text-snapshot)))
    (cond (snapshot (read-source-snapshot path snapshot))
          ((scheme-source-path? path) (call-with-input-source-file path read-all-as-string))
          (else (call-with-input-file path read-all-as-string)))))
(def (read-regular-source path (expected-length #f))
  ;; Private content path: the caller already checked regular-file status.
  ;; The path entry and the observed query share the same actual read value.
  (let (cache (source-read-cache))
    (def cached (if cache (hash-ref cache path missing-source-query) missing-source-query))
    (def text
      (if (not (eq? cached missing-source-query)) cached
        (let (read (begin (observe-read path)
                          (module-source-measure-operation 'source-read
                            (lambda () (read-source-text path expected-length)))))
          (record-physical-source-read! (string-length (source-text-content read)))
          (when cache (hash-put! cache path read))
          read)))
    (if expected-length text (materialize-source-text text))))

(def (read-large-source-matches? path expected snapshot)
  (observe-read path)
  (def text
    (source-text-content
      (module-source-measure-operation 'source-read
        (lambda () (read-source-snapshot path snapshot)))))
  (record-physical-source-read! (string-length text))
  (equal? expected text))

(def (module-source-text-guard path expected)
  (def expected-length (string-length expected))
  (if (or (< expected-length 32768) (not (scheme-source-path? path)))
    (lambda () (equal? expected (module-source-observe module-source-read path)))
    (let (snapshot (source-text->snapshot expected))
      (def (large-text-current?)
        (observe-read-request path)
        (unless (eq? (module-source-type path) 'regular)
          (error "module role must be a regular file" path))
        (def cache (source-read-cache))
        (def cached (if cache (hash-ref cache path missing-source-query) missing-source-query))
        (if (eq? cached missing-source-query)
          (read-large-source-matches? path expected snapshot)
          (equal? expected (source-text-content cached))))
      (lambda ()
        (if (current-module-source-observer)
          ;; Keep the original query key and read notifications. Ordinary
          ;; reads still receive their own mutable view of the cached text.
          (parameterize ((current-source-text-snapshot snapshot))
            (equal? expected
              (source-text-content (module-source-observe read-module-source path expected-length))))
          (module-source-observe large-text-current?))))))

(def (compiler-interface-info path)
  ;; The native importer owns .ssi paths. Bazel may project its Tree Artifact
  ;; files as symlinks; this is separate from admitting a source role.
  (unless (equal? (path-extension path) ".ssi")
    (error "native compiler interface must name an .ssi file" path))
  (observe-source 'stats)
  (def info (file-info path #t))
  (unless (eq? (file-info-type info) 'regular)
    (error "native compiler interface must resolve to a regular file" path))
  info)

(def (compiler-interface-read path)
  (observe-read-request path)
  (compiler-interface-info path)
  (read-regular-source path))

(def (module-compiler-interface-source interface-path)
  ;; Keep the import spelling in the original byte observations. The extent's
  ;; guard additionally binds the followed file identity, so identical bytes at
  ;; a different symlink target do not silently replace the admitted interface.
  (def initial-info (compiler-interface-info interface-path))
  (def initial-kind (module-source-type interface-path))
  (def (same-file? info)
    (and (equal? (file-info-device info) (file-info-device initial-info))
         (equal? (file-info-inode info) (file-info-inode initial-info))))
  (def observations
    (list (cons interface-path (compiler-interface-read interface-path))))
  (def (current!)
    (unless (and (equal? initial-kind (module-source-type interface-path))
                 (same-file? (compiler-interface-info interface-path)))
      (error "native compiler interface changed target; use a fresh source epoch" interface-path))
    (module-source-admit-current! observations "native compiler interface bytes changed"))
  (current!)
  (.o source-inputs: observations admit-current: current!))

;; Private per-admission observations; neither a field table nor a global log.
(defstruct source-observation (input message) final: #t)
(def (check-source-current! entry message)
  ;; Keep comparison reuse inside the EXISTING pure read window. Index by path,
  ;; then expected-text identity: hashing complete source texts on every hit
  ;; would replace a linear comparison with another linear operation. Distinct
  ;; expected revisions (including equal copies) must be checked independently.
  ;; Windows already require stable bytes/inputs; callbacks must end them.
  (def cache (source-read-cache))
  ;; Snapshot before any observer callback, including the comparison event.
  (def observed? (current-module-source-observer))
  (def key (and cache (cons check-source-current! (car entry))))
  (def checked (and cache (hash-get cache key)))
  (if (and checked
           (or (eq? (car checked) (cdr entry))
               (and (cdr checked) (hash-key? (cdr checked) (cdr entry)))))
    (observe-source 'source-comparison-hits)
    (begin
      (observe-source 'source-comparisons)
      (unless (if (cdr entry)
                (if (equal? (path-extension (car entry)) ".ssi")
                  (equal? (cdr entry) (compiler-interface-read (car entry)))
                  (and (eq? (module-source-type (car entry)) 'regular)
                     (equal? (cdr entry)
                       (if observed? (module-source-read (car entry))
                         (begin
                           (observe-read-request (car entry))
                           (read-regular-source (car entry)))))))
                (not (module-source-type (car entry))))
        (error message (car entry)))
      ;; A failed check never enrolls a comparison result. Observation collection
      ;; remains in module-source-admit-current!, outside this memoized work.
      (when cache
        ;; Keep the first expected identity directly. Only paths with another
        ;; successful identity need the table for additional expectations.
        (if (not checked)
          (hash-put! cache key (cons (cdr entry) #f))
          (let (additional (or (cdr checked)
                               (let (table (make-hash-table-eq))
                                 (set-cdr! checked table)
                                 table)))
            (hash-put! additional (cdr entry) #t)))))))
(def (call-with-collected-module-sources consume)
  (def by-path (make-hash-table))
  (def observed '())
  (def (collect! entry message)
    (def previous (or (hash-get by-path (car entry)) '()))
    ;; De-duplicate matching revisions without hashing whole source texts or
    ;; replacing an earlier revision of the same path with a later one.
    (unless (any (lambda (item)
                   (equal? (cdr (source-observation-input item)) (cdr entry))) previous)
      (let* ((input (cons (string-copy (car entry))
                         (and (cdr entry) (string-copy (cdr entry)))))
             (item (make-source-observation input message)))
        (hash-put! by-path (car input) (cons item previous))
        (set! observed (cons item observed)))))
  (def (current!)
    ;; No candidate traversal, and no re-reporting a replay into an outer scope.
    ;; Only actual admission checks enroll observations, not this final pass.
    (call-with-module-source-fresh-reads
      (lambda ()
        ;; The replay itself only checks retained observations. Start with
        ;; fresh bytes, then share physical reads within this one pure pass.
        ;; Never inherit an enclosing admission's pre-effect observations.
        (call-with-module-source-read-cache
          (lambda ()
            (for-each
              (lambda (item)
                (check-source-current! (source-observation-input item)
                                      (source-observation-message item)))
              (reverse observed)))))))
  (parameterize ((source-collectors (cons collect! (source-collectors))))
    (consume current!)))
(def (admit-source-observations! observations message)
  ;; One authority for JSON, runtime slot sources and publication guards. Nested
  ;; admission contributes observations to every active enclosing scope.
  (for-each
    (lambda (entry)
      (check-source-current! entry message)
      (for-each (lambda (collect!) (collect! entry message)) (source-collectors)))
    observations))
(def (module-source-admit-current! observations
        (message "stale selected build input; regenerate the build entry"))
  ;; This is the same closed filesystem window used by the enclosing guards,
  ;; not an admission result. Its query key includes the active collectors, so
  ;; a nested admission must still enroll its own complete observations.
  ;; Open observers keep every original callback and comparison in order.
  ;; With no collector, the per-source comparison index already avoids the
  ;; duplicate work. Do not allocate another traversal index on metadata-only
  ;; publication checks, where there is no collector enrollment to eliminate.
  (if (and (source-read-cache) (pair? (source-collectors))
           (not (current-module-source-observer)))
    (let* ((cache (source-read-cache))
           ;; As with check-source-current!'s expected-text index, use runtime
           ;; identity here: hashing complete source texts repeats linear work.
           ;; Inputs/bytes must remain stable within the existing pure window.
           (key (cons admit-source-observations! (source-collectors)))
           (batches (hash-get cache key)))
      (unless (and batches (hash-key? batches observations))
        (admit-source-observations! observations message)
        (unless batches
          (set! batches (make-hash-table-eq))
          (hash-put! cache key batches))
        ;; Only successful batches enter this collector-local traversal index.
        ;; Repeated equal requirements keep the collector's first diagnostic.
        (hash-put! batches observations #t)))
    (admit-source-observations! observations message)))
