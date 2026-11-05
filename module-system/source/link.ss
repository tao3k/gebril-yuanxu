;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generation-local linking over admitted source capabilities. The filesystem source adapter remains separate from runtime loading.
(import (only-in :std/list/list delete-duplicates/hash foldl)
        (only-in :clan/poo/prototype-map prototype-map prototype-map-ref prototype-map-put)
        (only-in :clan/poo/slot-observation without-observation)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        (runtime: :clan/poo/object)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/publication
        :yuanxu/module-system/source/admission
        (only-in :yuanxu/module-system/source/deferred-declaration module-binding-action)
        :yuanxu/module-system/source/selection
        :yuanxu/module-system/source/preparation
        :yuanxu/module-system/source/directory
        :yuanxu/module-system/source/reader
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?))
(export yuanxu-load-modules module-namespace-project)

;; Closed, branch-local projection of an admitted POO capability. Bindings are
;; ordinary POO metadata: exposed slot -> source slot symbol. The permitted
;; names constrain TARGETS, so a renamed hidden slot cannot acquire a getter.
;; No source value is read until native .get demands the projected slot.
(def (module-namespace-project source bindings permitted)
  (unless (and (object? source) (object? bindings)
               (list? permitted) (andmap symbol? permitted))
    (error "namespace projection requires POO bindings and permitted source names"))
  (def allowed
    (module-source-measure-operation 'namespace-permitted-index
      (lambda ()
        (def index (make-hash-table-eq))
        (for-each (lambda (name)
                    (unless (.slot? source name)
                      (error "permitted namespace target is absent" name))
                    (hash-put! index name #t))
                  permitted)
        index)))
  (def exposed
    (module-source-measure-operation 'namespace-enumeration (lambda () (.all-slots bindings))))
  ;; Each admitted row already knows its target. Compile that target into the
  ;; native slot spec; neither the permit index nor an alias map survives here.
  (let project ((remaining exposed) (slots '()))
    (if (null? remaining)
      (module-source-measure-operation 'namespace-slot-construction
        (lambda () (make-object slots: (reverse slots))))
      (let* ((name (car remaining))
             (target (module-source-measure-operation 'namespace-metadata-getter
                       (lambda () (.ref bindings name)))))
        (unless (and (symbol? name) (symbol? target))
          (error "namespace binding requires symbol names" name target))
        (if (hash-get allowed target)
          (project (cdr remaining)
            (cons (module-source-measure-operation 'namespace-alias-slot-spec
                    (lambda () (cons name ($thunk-slot-spec (lambda () (.ref source target))))))
                  slots))
          (project (cdr remaining) slots))))))

;; Namespace/selection does not construct a build Graph. Keep the existing
;; runtime lazy slot as the demand boundary, including source-only bootstrap.
;; Compiler coverage still includes source/build via build-projection's root.
;; Export admission owns its Gerbil import. Selecting build targets neither
;; publishes an export nor needs the artifact issuer's compiler closure.
(def export-publication
  (module-binding-action "yuanxu/admission/publication" 'selected-export-publication))
(def build-graph-producer
  (module-binding-action "yuanxu/module-system/source/build" 'module-build-graph))
;; Private admission carrier, not another namespace or semantic Graph. The
;; dependency list is the final receiver's already demanded symbol projection.
(defstruct linked-publication
  (source value evidence dependencies metadata-current metadata-entry metadata-tail metadata-roots)
  final: #t)
(defstruct linked-preparation (value metadata) final: #t)
;; A realized scope remains inspectable as a complete package value. Bind its
;; direct POO overrides onto the selected source scope, retaining that source's
;; prototypes and exact Contract declarations instead of importing another
;; evaluation context's ancestors. Ordinary scope admission still runs after it.
(def (bind-package-scope source-scope package-scope)
  (.mix slots: (object-slots package-scope)
        defaults: (object-defaults package-scope) source-scope))
;; Attribute effect boundaries without retaining their results or source reads.
(def (observe-link-stage stage thunk (current! #f))
  ;; Scope callbacks are separate effect boundaries. The check after a
  ;; successful callback runs before a later Contract/factory can restore its
  ;; changed source. Exceptions retain their original cause; no result or
  ;; currentness verdict is retained. Metadata selection does not call this
  ;; guarded business-scope path.
  (def (check!)
    (when current! (call-with-module-source-fresh-reads current!)))
  (def (invoke)
    (check!)
    (let (value (module-source-measure-operation (if (pair? stage) (car stage) stage) thunk))
      (check!)
      value))
  (let (observer (current-module-source-observer))
    (if (not observer) (invoke)
      (begin
        ;; Observer delivery is itself open. Do not carry a checked entry
        ;; across start delivery, or accept mutations made by end delivery.
        (check!)
        (let ((body-failed? #f) (body-failure #f))
         (let (value
              (dynamic-wind
                (lambda () (observer (list 'link-stage-start stage) 1))
                (lambda ()
                  (with-catch
                    (lambda (cause)
                      (set! body-failed? #t)
                      (set! body-failure cause)
                      (raise cause))
                    invoke))
                (lambda ()
                  (with-catch
                    (lambda (cause)
                      ;; End delivery runs during unwinding too. Keep BOTH
                      ;; actual causes, including a raised #f, in the existing
                      ;; Error payload rather than replacing the first error.
                      (if body-failed?
                        (error "module link stage and observer failed" stage body-failure cause)
                        (raise cause)))
                    (lambda () (observer (list 'link-stage-end stage) 1))))))
          (check!)
          value))))))
;; Capture the callback body only. Selection guards and observer delivery keep
;; their own checks and never become the callback's local dependencies.
(def (observe-supported-link-stage stage action current! retain!)
  (observe-link-stage stage
    (lambda ()
      (call-with-collected-module-sources
        (lambda (sources-current!)
          (call-with-publication-reads action
            (lambda (results reads-current! _roots)
              (retain! (lambda ()
                         (reads-current!)
                         (sources-current!)))
              results)))))
    current!))

(def (module-id-parts id)
  (let (parts (string-split (symbol->string id) #\/))
    (unless (and (pair? parts)
                 (andmap (lambda (part) (and (> (string-length part) 0)
                                             (not (member part '("." ".."))))) parts))
      (error "invalid qualified module identity" id))
    (map string->symbol parts)))
(def (scope-tree rows resolve)
  (let (names (delete-duplicates/hash (map caar rows) from-end?: #t))
    ;; Index only immutable namespace metadata. Original row occurrences remain
    ;; in source order; no scope resolver, Contract or business role runs here.
    ;; Native ordered maps avoid scanning every sibling for each cold name.
    (def groups
      (foldl (lambda (row index)
               (let (name (caar row))
                 (prototype-map-put index name
                   (cons row (prototype-map-ref index name '())))))
             (prototype-map '()) rows))
    (object<-fun
     (lambda (name)
       (let* ((children (reverse (prototype-map-ref groups name '())))
              (leaves (filter (lambda (row) (null? (cdar row))) children)))
         (cond
          ((and (pair? leaves) (pair? (cdr children)))
           (error "module namespace has a leaf/branch collision" name))
          ((pair? leaves) (resolve (cdar leaves)))
          (else (scope-tree (map (lambda (row) (cons (cdar row) (cdr row))) children)
                            resolve)))))
     keys: names)))
(def (yuanxu-load-modules source read-publication: (publication-reader #f)
                           module-view: (module-view #f))
  (load-module-source source publication-reader module-view module-publication-reader))
(def (load-module-source source publication-reader module-view reader-maker)
  (when (current-module-build-phase?)
    (error "Module build phase cannot reload the root module selection"))
  (if (and (string? source) (not publication-reader))
     (let ((reader #f) (context-construction-intact? (object-construction-current?)))
       ;; Namespace discovery owns only directory/init observations. Construct
       ;; the runtime interpreter and its Gerbil support on the first publication
       ;; demand, not while enumerating names or making inert module views.
       ;; This is the SAME reader/session, never a second Graph or approval.
       (def (reader-ref slot)
         (unless reader
           (unless (original-current? (.ref context 'generation))
             (error "stale module scope generation" (.ref context 'generation)))
           (set! reader (module-source-measure-operation 'reader-bootstrap reader-maker))
           ;; Runtime Gerbil bootstrap may initialize code. No directory approval
           ;; crosses that boundary, even before the first candidate is read.
           (unless (original-current? (.ref context 'generation))
             (error "stale module scope generation" (.ref context 'generation))))
         (.ref reader slot))
       (def context
         (module-source-measure-operation 'directory-context
           (lambda ()
             (module-directory-context source
               (lambda args (apply (reader-ref 'read) args))
               publication-prepares-source?: #t))))
       (def original-current? (.ref context 'current?))
       (.+ (link-module-context
        (.+ context (.o publication-inputs:
                       (lambda args (apply (reader-ref 'inputs) args))
                       publication-preparation:
                       (lambda args (apply (reader-ref 'preparation) args))
                       current?: (lambda (generation)
                                  (when reader ((.ref reader 'admit-current)))
                                  (original-current? generation))))
        #f #f module-view #f #f
        (lambda args (apply (reader-ref 'read-located) args)) original-current?
        (lambda args (apply (reader-ref 'read-candidate) args))
        (.ref context 'candidate-current?)
        (lambda (input (path #f))
          (and context-construction-intact? reader ((reader-ref 'metadata-state) input path)))
        (lambda ()
          (and context-construction-intact? reader ((reader-ref 'read-only-current?)))))
         (.o .refresh:
           (lambda ()
             ;; A fresh directory graph owns selection, publication and every
             ;; admission. Only native role contexts are offered by the reader;
             ;; its transfer checks the new graph's actual source authority.
             (load-module-source source #f module-view
               (if reader (lambda () ((.ref reader '.fork))) module-publication-reader))))))
     (link-module-context
       (if (string? source) (module-directory-context source publication-reader) source)
       #f #f module-view)))
(def (link-module-context context-value (realization #f) (original-graph #f) (module-view #f)
                          (source-publications #f) (source-prepared #f) (read-located #f)
                          (location-current? #f) (candidate-read #f) (candidate-location-current? #f)
                          (input-metadata-state #f) (reader-read-only-current? #f))
  (observe-link-stage 'context-admission
    (lambda () (admit-module-value! ModuleScopeContextContract context-value context-value)))
  (let ((cache (make-hash-table))
        (prepared (or source-prepared (make-hash-table)))
        (publications (or source-publications (make-hash-table)))
        (graphs (make-hash-table))
        (active (make-hash-table))
        (failed? #f)
        (generation-value (.ref context-value 'generation)))
    (def paired-context-current?
      (and read-located (module-source-object-policy (list context-value))))
    (def selection-tail (make-parameter #f))
    (def (prepared-input-state input)
      (or (and input-metadata-state (input-metadata-state input))
          (and (object? input) (object-%instance input) (object-%precedence-list input)
               (not (object-protocol input))
          (let* ((id (.ref/cached input 'identity (lambda () #f)))
                 (entry (and (symbol? id) (hash-get prepared id))))
            (and entry (eq? input (linked-preparation-value entry))
                 (linked-preparation-metadata entry))))))
    (def (with-source-metadata entries inputs action (input-state prepared-input-state))
      ;; Only native compiler metadata is passed by source/build. Callback,
      ;; observer, custom Context and realized-package routes keep fresh guards.
      (def closed?
        (and (not realization) input-metadata-state reader-read-only-current?
             (not (current-module-source-observer)) (owned-read-function-scope?)
             (object-construction-current?) paired-context-current? (paired-context-current?)
             (with-catch (lambda (_unsupported) #f)
               (lambda ()
                 (without-observation
                   (lambda ()
                     (and metadata-index
                          (.ref/cached metadata-index 'complete? (lambda () #f))
                          (= (hash-length publications)
                             (.ref/cached metadata-index 'count (lambda () -1)))
                          (module-source-measure-operation 'compiler-metadata-reader reader-read-only-current?)
                          (module-source-measure-operation 'compiler-metadata-inputs
                            (lambda ()
                              ;; The actual Graph constructor also owns inputs
                              ;; which were never Reader preparations. Consume
                              ;; its existing bound state, not a second origin
                              ;; registry or an object-supplied purity property.
                              (andmap (lambda (input)
                                (let (state (input-state input)) (and state (state)))) inputs)))
                          ;; Cold metadata may fill value caches, but must not
                          ;; invalidate a protected cache-miss record. Reuse the
                          ;; native issued DAG; do not reconstruct token bundles.
                          (let (roots (.ref/cached metadata-index 'roots (lambda () #f)))
                            (and roots
                              (let ((receivers (make-table test: eq?)) (safe? #t))
                                (for-each (lambda (input) (table-set! receivers input #t))
                                          (append entries inputs))
                                (module-source-measure-operation 'compiler-metadata-preflight
                                  (lambda ()
                                    (replay-slot-reads! roots
                                      (lambda (receiver key)
                                        (when (and (pair? key) (eq? (car key) 'cache-miss)
                                                   (table-ref receivers receiver #f))
                                          (set! safe? #f))))))
                                safe?))))))))))
      (module-source-measure-operation
        (if closed? 'compiler-source-shared 'compiler-source-independent)
        (lambda () (if closed? (call-with-module-source-read-cache action) (action)))))
    (def (candidate-location-current! id)
      ;; This closure belongs to the runtime paired directory factory. Share
      ;; only a pure filesystem window, ending BEFORE any reader/MOP callback.
      (when candidate-location-current?
        (call-with-module-source-read-cache
          (lambda ()
            (unless (candidate-location-current? generation-value id)
              (set! failed? #t)
              (error "stale module location generation" generation-value))))))
    ;; Package realization changes scope bindings, not the selected source
    ;; Graph. Preserve its identity and resolver result at this handoff; every
    ;; public use below still performs a fresh source/package boundary check.
    (when original-graph
      (hash-put! graphs (.ref context-value 'selected) (.ref original-graph 'selected-graph)))
    ;; The existing table inserts each immutable publication once. A normal
    ;; POO slot indexes its topology; cardinality changes invalidate that slot,
    ;; never authenticate live sources. The shared table may grow via another
    ;; realization, so inspect its ACTUAL cardinality on every boundary.
    (def metadata-index
      (and (object-construction-current?)
        (.o (:: index [])
          count: -1
          rows:
          (let (rows '())
            (hash-for-each (lambda (_id record) (set! rows (cons record rows))) publications)
            (reverse rows))
          complete?:
          (andmap (lambda (record)
                    (or (not (linked-publication-metadata-current record))
                        (and (linked-publication-metadata-entry record)
                             (linked-publication-metadata-tail record)
                             (list? (linked-publication-metadata-roots record)))))
                  (.get index rows))
          roots:
          (foldr append '()
            (map (lambda (record) (or (linked-publication-metadata-roots record) '()))
                 (.get index rows))))))
    (def (metadata-topology)
      ;; Private derived bookkeeping is not a semantic dependency of the
      ;; selected Graph. Its payload contains the SAME original issued reads;
      ;; fixed entry/tail checks below retain their original observation scope.
      (without-observation
        (lambda ()
          (def size (hash-length publications))
          (unless (= size (.get metadata-index count)) (.put! metadata-index 'count size))
          (values (.get metadata-index complete?) (.get metadata-index rows) (.get metadata-index roots)))))
    (def (check-publications!)
      (hash-for-each
        (lambda (_id record)
          (let (guard (linked-publication-metadata-current record))
            (when guard (guard)))) publications))
    (def (check-indexed-publications!)
      (defvalues (complete? rows roots)
        (module-source-measure-operation 'metadata-index metadata-topology))
      (if (not complete?) (check-publications!)
        (let ()
          (def entered? #f)
          (def (checkpoints!)
            (set! entered? #t)
            (for-each (lambda (record)
                        (let (entry! (linked-publication-metadata-entry record))
                          (when entry! (entry!)))) rows)
            (for-each (lambda (record)
                        (let (tail! (linked-publication-metadata-tail record))
                          (when tail! (tail!)))) rows))
          (def (replay!)
            (with-catch
              ;; Replay is read-only. Restore the original diagnostic without
              ;; turning a failed preflight into approval if its retry succeeds.
              (lambda (cause)
                (unless entered? (check-publications!))
                (raise cause))
              (lambda () (module-source-measure-replay roots checkpoints!))))
          ;; Establish all metadata BEFORE any checkpoint can mark a source
          ;; owner refused. Checkpoint failures then keep their original cause;
          ;; never rerun them under an already changed refusal flag.
          (replay!))))
    (def (check-current!)
      (unless ((.ref context-value 'current?) generation-value)
        (set! failed? #t)
        (error "stale module scope generation" generation-value))
      ;; The realized narrow guard is source-only. Full package effects
      ;; remain outside this boundary in the public/package guards.
      (when realization ((.ref realization 'sources-current)))
      ;; Pending and accepted records share this ONE existing index. Replaying
      ;; projected runtime evidence detects Contract/policy edits without
      ;; repeating classification or retaining discarded construction reads.
      ;; The existing pure query window permits native fixed checkpoints only.
      ;; Unknown contexts, changed constructors and observers keep the exact
      ;; original sequence. Every scope/Contract effect still has fresh guards.
      (if (and metadata-index paired-context-current? (paired-context-current?)
               (object-construction-current?) (not (current-module-source-observer))
               (owned-read-function-scope?))
        (check-indexed-publications!)
        (check-publications!)))
    (def (current! (origin 'link-current))
      (when failed? (error "module scope session was refused" generation-value))
      (module-source-measure-operation 'link-current
        (lambda ()
          (parameterize ((current-module-source-phase origin))
            (call-with-module-source-read-cache
              ;; Each occurrence authenticates its original issued MOP graph.
              ;; Only the nested filesystem observations may share bytes.
              check-current!))))
      (when (selection-tail) (set-box! (selection-tail) #f)))
    (def (dependency-scope owner alias provider-id baseline)
      (if (not realization) baseline
        (let (matches
               (filter (lambda (request)
                         (and (.slot? request 'configuration-owner)
                              (eq? owner (.ref request 'configuration-owner))
                              (eq? provider-id (.ref request 'build-owner))
                              (eq? alias (.ref request 'dependency-alias))))
                       (.ref original-graph 'external-packages)))
          (cond ((null? matches) baseline)
                ((pair? (cdr matches)) (error "ambiguous realized dependency" owner alias))
                (else
                 (let* ((request (car matches))
                        (packages (.ref realization 'packages))
                        (key (.ref request 'identity)))
                   (unless (.slot? packages key)
                     (error "missing realized dependency" owner alias key))
                   (bind-package-scope baseline (.ref (.ref packages key) 'scope))))))))
    ;; A direct package projection may specialize its owner's scope. Select
    ;; only this owner's results; never borrow a consumer's dependency scope.
    ;; A package contributes POO overrides to the source-owned scope. It must
    ;; not replace the source declaration merely to inject realized values.
    (def (realized-scope owner baseline)
      (if (not realization) baseline
        (let (scopes
               (filter-map
                (lambda (request)
                  (and (.slot? request 'scope-owner)
                       (eq? owner (.ref request 'scope-owner))
                       (let (value (.ref (.ref realization 'packages) (.ref request 'identity)))
                         (and (.slot? value 'scope) (.ref value 'scope)))))
                (.ref original-graph 'external-packages)))
          (cond ((null? scopes) baseline)
                ((null? (cdr scopes)) (bind-package-scope baseline (car scopes)))
                (else (error "multiple realized scopes for one publication" owner))))))
    (def (bind-exports scope baseline owner selection-value)
      (if (not (.slot? baseline 'admissions)) scope
        (let* ((declarations (.ref baseline 'admissions))
               (names (.all-slots declarations))
               ;; A config-shaped internal value is not a declared public
               ;; configuration interface. core.admissions owns that association.
               (scope (if (any (lambda (name)
                                 (equal? (.ref (.ref declarations name) 'export-path) '(config))) names)
                        (admit-module-configuration! scope baseline owner context-value)
                        scope))
               (bindings
                (filter-map
                 (lambda (name)
                   (let ((path (.ref (.ref declarations name) 'export-path)))
                     ;; Binding is an opt-in object protocol. No domain import,
                     ;; publication lookup or effect occurs while linking.
                     (and (= (length path) 1)
                       (let (value (.ref scope (car path)))
                         (and (object? value) (.slot? value '.bind-publication)
                              (cons (car path)
                                ((.ref value '.bind-publication)
                                 (lambda () (export-publication (list selection-value owner name)))
                                 owner name (and realization (.ref realization 'admit-current))))))))) names)))
          (if (null? bindings) scope (.+ scope (object<-alist bindings))))))
    (def (eligible! id path (location-only? #f) (candidate-location? #f))
      (def (entry! origin)
        (if (not location-only?) (current! origin)
          ;; This factory-owned operation reads only parsed intent, runtime
          ;; metadata policy and directory observations. Prior publications are
          ;; NOT its dependencies. The reader checks their complete support
          ;; before the first opaque preparation/expansion callback.
          (begin
            (when failed? (error "module scope session was refused" generation-value))
            (parameterize ((current-module-source-phase origin))
              (unless (if (and candidate-location? candidate-location-current?)
                        (candidate-location-current? generation-value id)
                        (location-current? generation-value))
                (set! failed? #t)
                (error "stale module location generation" generation-value))))))
      (entry! 'eligibility)
      (when (memq id (.ref context-value 'denied-modules))
        (error "required module disabled" (reverse (cons id path))
               (and (.slot? context-value 'init-source) (.ref context-value 'init-source))))
      (unless (memq id (.ref context-value 'module-ids))
        (unless (and (.slot? context-value 'eligible?)
                     ((.ref context-value 'eligible?) id))
          (error "module is outside selected source policy" (reverse (cons id path))))
        ;; Dynamic eligibility may run author code. Refuse a changed source
        ;; before reading its publication, not after initialization has run.
        (entry! 'eligibility-after-policy)))
    (def (publication-for id)
      ;; Only the runtime paired reader can execute this closed prefix. A custom
      ;; Context/reader keeps its full independent effect-boundary guards.
      (if (and candidate-read paired-context-current? location-current?
               (paired-context-current?) (module-publication-contract-current?)
               (yuanxu-module-source-ref-construction-current?)
               (not (hash-key? publications id)))
        (let* ((result
                (module-source-measure-operation 'candidate-read
                 (lambda () (candidate-read
                  (lambda ()
                    ;; A preceding OPEN fallback still closes before entering
                    ;; runtime execution. Closed private candidates have no
                    ;; published authority and need only operation support.
                    (when (and (selection-tail) (unbox (selection-tail)))
                      (current! 'candidate-after-open))
                    (eligible! id '() #t #t)
                    ((.ref context-value 'locate) id))
                  id context-value (lambda () (current! 'candidate-open))
                  (lambda () (candidate-location-current! id))))))
               (record (apply make-linked-publication result)))
          (unless (paired-context-current?)
            (set! failed? #t)
            (error "candidate Module Context changed" id))
          (hash-put! publications id record)
          record)
      (if (and paired-context-current? location-current? (paired-context-current?)
               (yuanxu-module-source-ref-construction-current?)
               (not (hash-key? publications id)))
        (publication/eligible id
          (lambda ()
            ;; Resume a tentative private dependency walk BEFORE another
            ;; directory/getter/import boundary. This full check and the
            ;; reader entry share only the existing CLOSED location window.
            (when (and (selection-tail) (unbox (selection-tail)))
              (current! 'publication-continuation-before-location))
            (eligible! id '() #t)))
        (begin (eligible! id '()) (publication/eligible id)))))
    (def (publication/eligible id (prefix #f))
      ;; Internal continuation of eligible!: callers below perform only private
      ;; hash lookups between admission and this lookup. No second source guard
      ;; is needed until a reader, validator or scope factory actually runs.
      (if (hash-key? publications id) (hash-ref publications id)
        (let* ((locate
                (lambda ()
                  (when prefix (prefix))
                  (let (source ((.ref context-value 'locate) id))
                    (unless (yuanxu-module-source-ref? source)
                      (error "module scope requires an admitted SourceRef" id source))
                    source)))
               (pair (module-source-measure-operation 'publication-read
                      (lambda () (call-with-values
                       (lambda ()
                         (if prefix (read-located locate)
                           (let (source (locate))
                             (values source ((.ref context-value 'read-publication) source)))))
                       cons))))
               (source-value (car pair))
               (publication-value (cdr pair))
               (reads (make-hash-table-eq))
               (evidence-value
                 (module-source-measure-operation 'publication-admission
                   (lambda ()
                     (call-with-publication-reads
                       (lambda ()
                         (admit-module-publication! source-value id publication-value context-value))
                       (lambda (results _current! roots)
                         (for-each (lambda (read) (hash-put! reads read #t)) roots)
                         results)
                       ;; A caller's getter still owns EVERY dependency edge
                       ;; occurrence. This capture is not a replay-root set.
                       unique-roots?: #f))))
               (checked-publication (.ref evidence-value 'candidate))
               (dependency-ids
                 (module-publication-dependency-projection checked-publication
                   (lambda (read) (hash-key? reads read))))
               (record (make-linked-publication source-value checked-publication
                                                evidence-value dependency-ids #f #f #f #f)))
          ;; Only the runtime paired selection can postpone this check across
          ;; a private symbol/hash walk. No POO getter or author callback is
          ;; allowed in that continuation. Context changes retain the full tail.
          (if (and dependency-ids prefix (selection-tail) (paired-context-current?))
            (set-box! (selection-tail) #t)
            (current! 'publication-admitted))
          (hash-put! publications id record)
          record)))
    (def (dependencies-for entry id)
      (or (linked-publication-dependencies entry)
        ;; A callback invalidated/replaced cached metadata. Its ordinary tail
        ;; already ran; guard the new getters and their return independently.
        (begin
          (current! 'dependency-projection-before)
          (let* ((requirements (.ref (.ref (linked-publication-value entry) 'core) 'requires))
                 (ids (map (lambda (name) (.ref (.ref requirements name) 'module-id))
                           (.all-slots requirements))))
            (unless (andmap symbol? ids)
              (error "module dependency projection requires symbol identities" id))
            (current! 'dependency-projection-after)
            ids))))
    (def (resolve-selection-graph roots)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         (current! 'graph-before)
         (if (hash-key? graphs roots) (hash-ref graphs roots)
           (let (graph (parameterize ((selection-tail (box #f)))
                        (select-module-graph
                         context-value roots
                         (lambda (id) (linked-publication-value (publication-for id)))
                         (lambda ()
                           ;; Closed call-site labels only; attribution never
                           ;; changes source-window or query-reuse identity.
                           (current!
                             (case (current-module-source-phase)
                               ((build-entry) 'graph-current/build-entry)
                               ((build-current) 'graph-current/build-current)
                               ((build-finalize) 'graph-current/build-finalize)
                               ((build-external-before) 'graph-current/build-external-before)
                               ((build-external-after) 'graph-current/build-external-after)
                               ((build-admit-before) 'graph-current/build-admit-before)
                               ((build-admit-after) 'graph-current/build-admit-after)
                               ((configuration-current) 'graph-current/configuration-reader)
                               ((configuration-public) 'graph-current/configuration-public)
                               ((configuration-pre-bootstrap) 'graph-current/configuration-pre-bootstrap)
                               (else 'graph-current))))
                         (and paired-context-current? (paired-context-current?)
                              (module-publication-contract-current?)
                           (lambda (id)
                             (let (entry (publication-for id))
                               (values (linked-publication-value entry)
                                       (dependencies-for entry id))))))))
             ;; select-module-graph owns its final check after author slots.
             ;; Only this private index insertion follows, with no new effect.
             (hash-put! graphs roots graph)
             graph)))))
    (def (link id path)
      (eligible! id path)
      (cond
       ((hash-key? active id) (error "module dependency cycle" (reverse (cons id path))))
       ((hash-key? cache id) (hash-ref cache id))
       (else
        (hash-put! active id #t)
        (dynamic-wind
         void
         (lambda ()
           (let* ((published (publication/eligible id))
                  (source-value (linked-publication-source published))
                  (publication-value (linked-publication-value published))
                  (publication-evidence-value (linked-publication-evidence published)))
             (let* ((baseline (.ref publication-value 'core))
                    (requirements (.ref baseline 'requires))
                    (records
                     (object<-alist
                      (map (lambda (alias)
                             (let (checks '())
                               (def (edge-stage name action)
                                 (observe-supported-link-stage (list name id alias) action current!
                                   (lambda (check!) (set! checks (cons check! checks)))))
                               (let* ((requirement (.ref requirements alias))
                                    (base-record (link (.ref requirement 'module-id) (cons id path)))
                                    (interface?
                                     (requirement-option requirement 'view))
                                    (upstream (.ref base-record (if interface? 'interface 'scope)))
                                    (package-scope
                                     (if interface? upstream
                                       (dependency-scope id alias (.ref requirement 'module-id) upstream)))
                                    (refine (requirement-option requirement 'refine))
                                    (refined
                                     (if refine
                                       (edge-stage 'requirement-refinement
                                         (lambda ()
                                           ;; Same runtime write fence used when a method
                                           ;; declaration specializes an existing receiver.
                                           (instantiate-object! package-scope)
                                           (parameterize
                                               ((active-object-constructions
                                                 (cons package-scope
                                                       (cons upstream (active-object-constructions)))))
                                             (refine package-scope))))
                                       package-scope))
                                    (provider-evidence
                                     (cond
                                      (interface?
                                       (edge-stage 'requirement-interface-admission
                                         (lambda ()
                                           (admit-module-value! ModuleInterfaceViewContract upstream context-value))))
                                      ((eq? refined upstream)
                                       (.ref base-record 'scope-evidence))
                                      (else
                                       (edge-stage 'requirement-provider-admission
                                         (lambda ()
                                           (admit-module-value!
                                             (.ref (.ref (.ref base-record 'publication) 'core) 'scope-contract)
                                             refined context-value))))))
                                    (effective-scope (.ref provider-evidence 'candidate))
                                    (contract (requirement-option requirement 'contract))
                                    (evidence
                                     (if contract
                                       (edge-stage 'requirement-admission
                                         (lambda ()
                                           (admit-module-value!
                                             contract effective-scope context-value)))
                                       provider-evidence)))
                               (cons alias
                                 (let ((provider base-record)
                                       (scope (.ref evidence 'candidate))
                                       (requirement-evidence evidence)
                                       (edge-checks (reverse checks)))
                                   (.o provider scope provider-evidence requirement-evidence
                                       admit-current: (lambda ()
                                                        (current! 'requirement-current-before)
                                                        (for-each (lambda (check!) (check!)) edge-checks)
                                                        (current! 'requirement-current-after))))))))
                           (.all-slots requirements))))
                    (bindings (object<-alist
                               (map (lambda (alias)
                                      (cons alias (.ref (.ref records alias) 'scope)))
                                    (.all-slots records))))
                    (interface
                     (.o identity: id
                         requires: (object<-alist
                          (filter-map
                           (lambda (alias)
                             (let (requirement (.ref requirements alias))
                               (and (requirement-option requirement 'publish?)
                                    (cons alias (.ref bindings alias)))))
                           (.all-slots requirements)))))
                    (construction-current! void)
                    (unbound-scope
                     (observe-supported-link-stage (list 'scope-factory id)
                       (lambda () (realized-scope id ((.ref baseline 'link) bindings)))
                       current!
                       (lambda (check!) (set! construction-current! check!))))
                    (scope-value
                     (if (.slot? baseline 'admissions)
                       (observe-link-stage (list 'scope-publication-binding id)
                         (lambda () (bind-exports unbound-scope baseline id selection-value))
                         current!)
                       unbound-scope))
                    (scope-evidence-value
                     (observe-link-stage (list 'scope-admission id)
                       (lambda ()
                         (admit-module-value! (.ref baseline 'scope-contract) scope-value context-value))
                       current!))
                    (record
                     (let ((admit-construction-current
                            (lambda ()
                              (current! 'scope-construction-current-before)
                              (construction-current!)
                              (current! 'scope-construction-current-after)))
                           (identity id) (generation generation-value) (source source-value)
                           (publication publication-value) (publication-evidence publication-evidence-value)
                           (dependency-records records) (scope (.ref scope-evidence-value 'candidate))
                           (scope-evidence scope-evidence-value))
                       (.o identity generation source publication publication-evidence
                           dependency-records scope scope-evidence interface
                           admit-construction-current))))
               (current! 'scope-linked)
               (hash-put! cache id record)
               record)))
         (lambda () (hash-remove! active id))))))
    (def (resolve id)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         ;; Auto discovery adds only this demand root; selected init roots still
         ;; participate in the same admission, conflict and ordering policy.
         (let* ((roots (.ref context-value 'selected))
                (demand (if (memq id roots) roots (append roots (list id)))))
           ;; An existing Graph needs no traversal here: only this private
           ;; lookup precedes link's fresh eligibility/source guard. A new
           ;; demand still runs the full resolver and its post-author guard.
           (unless (hash-key? graphs demand) (resolve-selection-graph demand)))
         (link id '()))))
    (def (prepare id)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         (eligible! id '())
         (let (value
               (if (hash-key? prepared id) (linked-preparation-value (hash-ref prepared id))
                 (let* ((published (publication/eligible id))
                        (source-value (linked-publication-source published))
                        (base (if (.slot? context-value 'publication-preparation)
                                ((.ref context-value 'publication-preparation) source-value)
                                (yuanxu-prepare-module-publication source-value)))
                        (base-state (and input-metadata-state
                                         (input-metadata-state base (yuanxu-module-source-ref-value source-value))))
                        (related (if (.slot? context-value 'publication-preparation)
                                   (.ref base 'source-dependencies)
                                   (if (.slot? context-value 'publication-inputs)
                                     ((.ref context-value 'publication-inputs) source-value) '())))
                        (construction-intact? (object-construction-current?))
                        (value (.+ base
                                   (.o generation: generation-value source-dependencies: related
                                       admit-current:
                                       (lambda ()
                                         (call-with-module-source-read-cache
                                           (lambda ()
                                             (current! 'prepared-input-before)
                                             ((.ref base 'admit-current))
                                             (current! 'prepared-input-after))))))))
                   (unless (eq? id (.ref value 'identity))
                     (error "prepared publication source owner mismatch" id value))
                   (hash-put! prepared id
                     (make-linked-preparation value
                       (and construction-intact? (object-construction-current?) base-state
                         (let (metadata (module-source-object-policy (list value)))
                           (lambda () (and (metadata) (base-state))))))) value)))
           ;; Preparation is finished. These are adjacent source-only guards;
           ;; do not extend this scope over publication reading or admission.
           (call-with-module-source-read-cache
             (lambda ()
               ((.ref value 'admit-current))
               (current! 'prepared-after)))
           value))))
    ;; Slot caching belongs to this immutable generation. Consumers must call
    ;; admit-current before publishing/using a Graph; cached slots are not live IO.
    (def selection-value
      (.o self: result generation: generation-value
        context: context-value
        sources-current: current!
        package-current: (and realization (.ref realization 'admit-current))
        admit-current:
        (lambda ()
          (current!)
          ;; Without package admission there is no effect between these checks.
          (when realization
            ((.ref realization 'admit-current))
            (current!)))
        prepare-publication: prepare
        .selected-record:
        (lambda (owner)
          ;; Private Graph/member lookups precede link's fresh eligibility
          ;; guard. New roots still require the resolver's full admission.
          (let* ((roots (.ref context-value 'selected))
                 (graph (if (hash-key? graphs roots) (hash-ref graphs roots)
                          (resolve-selection-graph roots))))
            (unless (memq owner (.ref graph 'module-order))
              (error "admission owner is outside selected Graph" owner))
            (link owner '())))
        .with-packages:
        (lambda (package-result)
          (unless (eq? (.ref package-result 'build-graph) build-graph)
            (error "realized packages belong to a different selected Graph"))
          (observe-link-stage 'package-handoff
            (lambda () ((.ref package-result 'admit-current))))
          ;; Realization changes dependency scopes, never the selected source
          ;; publication identities already retained by the build Graph.
          (link-module-context context-value package-result build-graph module-view
                               publications prepared))
        modules:
        (let (resolve-scope
               (lambda (id)
                 (if module-view
                   (module-view id (lambda () (.ref (resolve id) 'scope)))
                   (.ref (resolve id) 'scope))))
          (or (and (.slot? context-value 'namespace)
                   ((.ref context-value 'namespace) resolve-scope))
              (scope-tree (map (lambda (id) (cons (module-id-parts id) id))
                               (.ref context-value 'selected)) resolve-scope)))
        ;; This immutable snapshot has exactly the init roots. Auto namespace
        ;; reads admit an additional bounded demand; they do not rewrite init.
        build-graph: (or original-graph
                        (build-graph-producer (list selected-graph prepare with-source-metadata prepared-input-state)))
        .build-graph-for:
        (lambda (roots)
          (build-graph-producer
            (list (resolve-selection-graph roots) prepare with-source-metadata prepared-input-state)))
        selected-graph: (resolve-selection-graph (.ref context-value 'selected))
        selected-records: (begin (resolve-selection-graph (.ref context-value 'selected))
                                 (map resolve (.ref context-value 'selected)))
        dependency-order:
        (.ref (resolve-selection-graph (.ref context-value 'selected)) 'module-order)))
    selection-value))
