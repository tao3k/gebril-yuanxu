;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generation-local linking over admitted source capabilities. The filesystem source adapter remains separate from runtime loading.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (only-in :clan/poo/object .o .+ .cc .mix .ref .slot? .all-slots object?
                 object-slots object-defaults object<-alist object<-fun)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/publication
        :yuanxu/module-system/source/admission
        (only-in :yuanxu/module-system/source/build module-build-graph)
        :yuanxu/module-system/source/selection
        :yuanxu/module-system/source/preparation
        :yuanxu/module-system/source/directory
        :yuanxu/module-system/source/reader
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?))
(export yuanxu-load-modules)
;; Private admission carrier, not another namespace or semantic Graph. The
;; dependency list is the final receiver's already demanded symbol projection.
(defstruct linked-publication (source value evidence dependencies metadata-current) final: #t)
;; A realized scope remains inspectable as a complete package value. Bind its
;; direct POO overrides onto the selected source scope, retaining that source's
;; prototypes and exact Contract declarations instead of importing another
;; evaluation context's ancestors. Ordinary scope admission still runs after it.
(def (bind-package-scope source-scope package-scope)
  (.mix slots: (object-slots package-scope)
        defaults: (object-defaults package-scope) source-scope))
;; Attribute effect boundaries without retaining their results or source reads.
(def (observe-link-stage stage thunk)
  (let (observer (current-module-source-observer))
    (if (not observer) (thunk)
      (dynamic-wind
        (lambda () (observer (list 'link-stage-start stage) 1))
        thunk
        (lambda () (observer (list 'link-stage-end stage) 1))))))
(def (module-id-parts id)
  (let (parts (string-split (symbol->string id) #\/))
    (unless (and (pair? parts)
                 (andmap (lambda (part) (and (> (string-length part) 0)
                                             (not (member part '("." ".."))))) parts))
      (error "invalid qualified module identity" id))
    (map string->symbol parts)))
(def (scope-tree rows resolve)
  (let (names (delete-duplicates/hash (map caar rows) from-end?: #t))
    (object<-fun
     (lambda (name)
       (let* ((children (filter (lambda (row) (eq? (caar row) name)) rows))
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
  (when (current-module-build-phase?)
    (error "Module build phase cannot reload the root module selection"))
  (if (and (string? source) (not publication-reader))
     (let ((reader #f))
       ;; Namespace discovery owns only directory/init observations. Construct
       ;; the native interpreter and its SDK support on the first publication
       ;; demand, not while enumerating names or making inert module views.
       ;; This is the SAME reader/session, never a second Graph or approval.
       (def (reader-ref slot)
         (unless reader
           (unless (original-current? (.ref context 'generation))
             (error "stale module scope generation" (.ref context 'generation)))
           (set! reader (module-source-measure-operation 'reader-bootstrap module-publication-reader))
           ;; Native SDK bootstrap may initialize code. No directory approval
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
       (link-module-context
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
        (.ref context 'candidate-current?)))
     (link-module-context
       (if (string? source) (module-directory-context source publication-reader) source)
       #f #f module-view)))
(def (link-module-context context-value (realization #f) (original-graph #f) (module-view #f)
                          (source-publications #f) (source-prepared #f) (read-located #f)
                          (location-current? #f) (candidate-read #f) (candidate-location-current? #f))
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
    (def (candidate-location-current! id)
      ;; This closure belongs to the native paired directory factory. Share
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
    (def (check-current!)
      (unless ((.ref context-value 'current?) generation-value)
        (set! failed? #t)
        (error "stale module scope generation" generation-value))
      ;; The realized narrow guard is source-only. Full package effects
      ;; remain outside this boundary in the public/package guards.
      (when realization ((.ref realization 'sources-current)))
      ;; Pending and accepted records share this ONE existing index. Replaying
      ;; projected native evidence detects Contract/policy edits without
      ;; repeating classification or retaining discarded construction reads.
      (hash-for-each
        (lambda (_id record)
          (let (guard (linked-publication-metadata-current record))
            (when guard (guard)))) publications))
    (def (current! (origin 'link-current))
      (when failed? (error "module scope session was refused" generation-value))
      (module-source-measure-operation 'link-current
        (lambda ()
          (parameterize ((current-module-source-phase origin))
            (call-with-module-source-read-cache
              (lambda () (module-source-observe check-current!))))))
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
                                ((.ref value '.bind-publication) selection-value owner name
                                 (and realization (.ref realization 'admit-current))))))))) names)))
          (if (null? bindings) scope (.+ scope (object<-alist bindings))))))
    (def (eligible! id path (location-only? #f) (candidate-location? #f))
      (def (entry! origin)
        (if (not location-only?) (current! origin)
          ;; This factory-owned operation reads only parsed intent, native
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
      ;; Only the native paired reader can execute this closed prefix. A custom
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
                    ;; native execution. Closed private candidates have no
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
                     (call-with-slot-read-observer
                       (lambda (read) (hash-put! reads read #t))
                       (lambda ()
                         (admit-module-publication! source-value id publication-value context-value))))))
               (checked-publication (.ref evidence-value 'candidate))
               (dependency-ids
                 (module-publication-dependency-projection checked-publication
                   (lambda (read) (hash-key? reads read))))
               (record (make-linked-publication source-value checked-publication
                                                evidence-value dependency-ids #f)))
          ;; Only the native paired selection can postpone this check across
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
                             (let* ((requirement (.ref requirements alias))
                                    (base-record (link (.ref requirement 'module-id) (cons id path)))
                                    (effective-scope
                                     (dependency-scope id alias (.ref requirement 'module-id)
                                                       (.ref base-record 'scope)))
                                    (record (if (eq? effective-scope (.ref base-record 'scope)) base-record
                                              (.cc base-record 'scope effective-scope)))
                                    (evidence (admit-module-value!
                                               (.ref requirement 'contract)
                                               (.ref record 'scope) context-value)))
                               (cons alias
                                 (let ((provider record) (requirement-evidence evidence))
                                   (.o provider requirement-evidence)))))
                           (.all-slots requirements))))
                    (bindings (object<-alist
                               (map (lambda (alias)
                                      (cons alias (.ref (.ref (.ref records alias) 'requirement-evidence) 'candidate)))
                                    (.all-slots records))))
                    (scope-value (observe-link-stage (list 'scope-factory id)
                                   (lambda ()
                                     (bind-exports
                                       (realized-scope id ((.ref baseline 'link) bindings))
                                                   baseline id selection-value))))
                    (scope-evidence-value
                     (observe-link-stage (list 'scope-admission id)
                       (lambda ()
                         (admit-module-value! (.ref baseline 'scope-contract) scope-value context-value))))
                    (record
                     (let ((identity id) (generation generation-value) (source source-value)
                           (publication publication-value) (publication-evidence publication-evidence-value)
                           (dependency-records records) (scope (.ref scope-evidence-value 'candidate))
                           (scope-evidence scope-evidence-value))
                       (.o identity generation source publication publication-evidence
                           dependency-records scope scope-evidence))))
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
               (if (hash-key? prepared id) (hash-ref prepared id)
                 (let* ((published (publication/eligible id))
                        (source-value (linked-publication-source published))
                        (base (if (.slot? context-value 'publication-preparation)
                                ((.ref context-value 'publication-preparation) source-value)
                                (yuanxu-prepare-module-publication source-value)))
                        (related (if (.slot? context-value 'publication-preparation)
                                   (.ref base 'source-dependencies)
                                   (if (.slot? context-value 'publication-inputs)
                                     ((.ref context-value 'publication-inputs) source-value) '())))
                        (value (.+ base
                                   (.o generation: generation-value source-dependencies: related
                                       admit-current:
                                       (lambda ()
                                         (call-with-module-source-read-cache
                                           (lambda ()
                                             (current!)
                                             ((.ref base 'admit-current))
                                             (current!))))))))
                   (unless (eq? id (.ref value 'identity))
                     (error "prepared publication source owner mismatch" id value))
                   (hash-put! prepared id value) value)))
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
        build-graph: (or original-graph (module-build-graph selected-graph prepare))
        selected-graph: (resolve-selection-graph (.ref context-value 'selected))
        selected-records: (begin (resolve-selection-graph (.ref context-value 'selected))
                                 (map resolve (.ref context-value 'selected)))
        dependency-order:
        (.ref (resolve-selection-graph (.ref context-value 'selected)) 'module-order)))
    selection-value))
