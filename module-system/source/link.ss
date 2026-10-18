;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generation-local linking over admitted source capabilities. The filesystem source adapter remains separate from runtime loading.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .+ .cc .ref .slot? .all-slots object? object<-alist object<-fun)
        :core/module-system/source/objects
        :core/module-system/source/publication
        :core/module-system/source/admission
        (only-in :core/module-system/source/build module-build-graph)
        :core/module-system/source/selection
        :core/module-system/source/preparation
        :core/module-system/source/directory
        :core/module-system/source/reader
        (only-in :core/module-system/source/declaration current-module-build-phase?))
(export poo-flow-load-modules)
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
(def (poo-flow-load-modules source read-publication: (publication-reader #f)
                           module-view: (module-view #f))
  (when (current-module-build-phase?)
    (error "Module build phase cannot reload the root module selection"))
  (link-module-context
   (if (and (string? source) (not publication-reader))
     (let* ((reader (module-publication-reader))
            (context (module-directory-context source (.ref reader 'read)))
            (original-current? (.ref context 'current?)))
       (.+ context (.o publication-inputs: (.ref reader 'inputs)
                       current?: (lambda (generation)
                                  ((.ref reader 'admit-current))
                                  (original-current? generation)))))
     (if (string? source) (module-directory-context source publication-reader) source))
   #f #f module-view))
(def (link-module-context context-value (realization #f) (original-graph #f) (module-view #f)
                          (source-publications #f) (source-prepared #f))
  (admit-module-value! ModuleScopeContextContract context-value context-value)
  (let ((cache (make-hash-table))
        (prepared (or source-prepared (make-hash-table)))
        (publications (or source-publications (make-hash-table)))
        (graphs (make-hash-table))
        (active (make-hash-table))
        (failed? #f)
        (generation-value (.ref context-value 'generation)))
    (def (check-current!)
      (unless ((.ref context-value 'current?) generation-value)
        (set! failed? #t)
        (error "stale module scope generation" generation-value))
      ;; The realized narrow guard is source-only. Full package effects
      ;; remain outside this boundary in the public/package guards.
      (when realization ((.ref realization 'sources-current))))
    (def (current! (origin 'link-current))
      (when failed? (error "module scope session was refused" generation-value))
      (parameterize ((current-module-source-phase origin))
        (call-with-module-source-read-cache
          (lambda () (module-source-observe check-current!)))))
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
                   (.ref (.ref packages key) 'scope)))))))
    (def (bind-exports scope baseline owner selection-value)
      (if (not (.slot? baseline 'admissions)) scope
        (let* ((declarations (.ref baseline 'admissions))
               (names (.all-slots declarations))
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
    (def (eligible! id path)
      (current! 'eligibility)
      (when (memq id (.ref context-value 'denied-modules))
        (error "required module disabled" (reverse (cons id path))
               (and (.slot? context-value 'init-source) (.ref context-value 'init-source))))
      (unless (memq id (.ref context-value 'module-ids))
        (unless (and (.slot? context-value 'eligible?)
                     ((.ref context-value 'eligible?) id))
          (error "module is outside selected source policy" (reverse (cons id path))))
        ;; Dynamic eligibility may run author code. Refuse a changed source
        ;; before reading its publication, not after initialization has run.
        (current! 'eligibility-after-policy)))
    (def (publication-for id)
      (eligible! id '())
      (publication/eligible id))
    (def (publication/eligible id)
      ;; Internal continuation of eligible!: callers below perform only private
      ;; hash lookups between admission and this lookup. No second source guard
      ;; is needed until a reader, validator or scope factory actually runs.
      (if (hash-key? publications id) (hash-ref publications id)
        (let* ((source-value ((.ref context-value 'locate) id))
               (_source-admitted
                (unless (poo-flow-module-source-ref? source-value)
                  (error "module scope requires an admitted SourceRef" id source-value)))
               (publication-value ((.ref context-value 'read-publication) source-value))
               (evidence-value (admit-module-publication! source-value id publication-value context-value))
               (record (.o source: source-value publication: publication-value evidence: evidence-value)))
          (current! 'publication-admitted)
          (hash-put! publications id record)
          record)))
    (def (resolve-selection-graph roots)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         (current! 'graph-before)
         (if (hash-key? graphs roots) (hash-ref graphs roots)
           (let (graph (select-module-graph
                         context-value roots
                         (lambda (id) (.ref (publication-for id) 'publication))
                         (lambda () (current! 'graph-current))))
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
                  (source-value (.ref published 'source))
                  (publication-value (.ref published 'publication))
                  (publication-evidence-value (.ref published 'evidence)))
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
                               (cons alias (.o provider: record requirement-evidence: evidence))))
                           (.all-slots requirements))))
                    (bindings (object<-alist
                               (map (lambda (alias)
                                      (cons alias (.ref (.ref (.ref records alias) 'provider) 'scope)))
                                    (.all-slots records))))
                    (scope-value (bind-exports ((.ref baseline 'link) bindings) baseline id selection-value))
                    (scope-evidence-value
                     (admit-module-value! (.ref baseline 'scope-contract) scope-value context-value))
                    (record (.o identity: id generation: generation-value source: source-value
                                publication: publication-value publication-evidence: publication-evidence-value
                                dependency-records: records scope: scope-value scope-evidence: scope-evidence-value)))
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
         (let (roots (.ref context-value 'selected))
           (resolve-selection-graph (if (memq id roots) roots (append roots (list id)))))
         (link id '()))))
    (def (prepare id)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         (eligible! id '())
         (let (value
               (if (hash-key? prepared id) (hash-ref prepared id)
                 (let* ((published (publication/eligible id))
                        (source-value (.ref published 'source))
                        (related (if (.slot? context-value 'publication-inputs)
                                   ((.ref context-value 'publication-inputs) source-value) '()))
                        (value (.+ (poo-flow-prepare-module-publication source-value admit-context: current!)
                                   (.o generation: generation-value source-dependencies: related))))
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
      (.o (:: result) generation: generation-value
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
          (current!)
          (let (graph (resolve-selection-graph (.ref context-value 'selected)))
            (unless (memq owner (.ref graph 'module-order))
              (error "admission owner is outside selected Graph" owner))
            (let (record (link owner '())) (current!) record)))
        .with-packages:
        (lambda (package-result)
          (unless (eq? (.ref package-result 'build-graph) build-graph)
            (error "realized packages belong to a different selected Graph"))
          ((.ref package-result 'admit-current))
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
