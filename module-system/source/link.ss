;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generation-local linking over admitted source capabilities. The filesystem source adapter remains separate from runtime loading.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .+ .ref .slot? .all-slots object<-alist object<-fun)
        :core/module-system/source/objects
        :core/module-system/source/publication
        :core/module-system/source/admission
        (only-in :core/module-system/source/build module-build-graph)
        :core/module-system/source/selection
        :core/module-system/source/preparation
        :core/module-system/source/directory
        :core/module-system/source/reader)
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
(def (poo-flow-load-modules source read-publication: (publication-reader #f))
  (link-module-context
   (if (and (string? source) (not publication-reader))
     (let* ((reader (module-publication-reader))
            (context (module-directory-context source (.ref reader 'read)))
            (original-current? (.ref context 'current?)))
       (.+ context (.o publication-inputs: (.ref reader 'inputs)
                       current?: (lambda (generation)
                                  ((.ref reader 'admit-current))
                                  (original-current? generation)))))
     (if (string? source) (module-directory-context source publication-reader) source))))
(def (link-module-context context-value)
  (admit-module-value! ModuleScopeContextContract context-value context-value)
  (let ((cache (make-hash-table))
        (prepared (make-hash-table))
        (publications (make-hash-table))
        (graphs (make-hash-table))
        (active (make-hash-table))
        (failed? #f)
        (generation-value (.ref context-value 'generation)))
    (def (current!)
      (when failed? (error "module scope session was refused" generation-value))
      (unless ((.ref context-value 'current?) generation-value)
        (set! failed? #t)
        (error "stale module scope generation" generation-value)))
    (def (eligible! id path)
      (current!)
      (when (memq id (.ref context-value 'denied-modules))
        (error "required module disabled" (reverse (cons id path))
               (and (.slot? context-value 'init-source) (.ref context-value 'init-source))))
      (unless (or (memq id (.ref context-value 'module-ids))
                  (and (.slot? context-value 'eligible?) ((.ref context-value 'eligible?) id)))
        (error "module is outside selected source policy" (reverse (cons id path)))))
    (def (publication-for id)
      (eligible! id '())
      (if (hash-key? publications id) (hash-ref publications id)
        (let* ((source-value ((.ref context-value 'locate) id))
               (_source-admitted
                (unless (poo-flow-module-source-ref? source-value)
                  (error "module scope requires an admitted SourceRef" id source-value)))
               (publication-value ((.ref context-value 'read-publication) source-value))
               (evidence-value (admit-module-publication! source-value id publication-value context-value))
               (record (.o source: source-value publication: publication-value evidence: evidence-value)))
          (current!)
          (hash-put! publications id record)
          record)))
    (def (resolve-selection-graph roots)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         (current!)
         (if (hash-key? graphs roots) (hash-ref graphs roots)
           (let (graph (select-module-graph
                         context-value roots
                         (lambda (id) (.ref (publication-for id) 'publication)) current!))
             (current!)
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
           (let* ((published (publication-for id))
                  (source-value (.ref published 'source))
                  (publication-value (.ref published 'publication))
                  (publication-evidence-value (.ref published 'evidence)))
             (let* ((baseline (.ref publication-value 'core))
                    (requirements (.ref baseline 'requires))
                    (records
                     (object<-alist
                      (map (lambda (alias)
                             (let* ((requirement (.ref requirements alias))
                                    (record (link (.ref requirement 'module-id) (cons id path)))
                                    (evidence (admit-module-value!
                                               (.ref requirement 'contract)
                                               (.ref record 'scope) context-value)))
                               (cons alias (.o provider: record requirement-evidence: evidence))))
                           (.all-slots requirements))))
                    (bindings (object<-alist
                               (map (lambda (alias)
                                      (cons alias (.ref (.ref (.ref records alias) 'provider) 'scope)))
                                    (.all-slots records))))
                    (scope-value ((.ref baseline 'link) bindings))
                    (scope-evidence-value
                     (admit-module-value! (.ref baseline 'scope-contract) scope-value context-value))
                    (record (.o identity: id generation: generation-value source: source-value
                                publication: publication-value publication-evidence: publication-evidence-value
                                dependency-records: records scope: scope-value scope-evidence: scope-evidence-value)))
               (current!)
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
                 (let* ((published (publication-for id))
                        (source-value (.ref published 'source))
                        (related (if (.slot? context-value 'publication-inputs)
                                   ((.ref context-value 'publication-inputs) source-value) '()))
                        (value (.+ (poo-flow-prepare-module-publication source-value admit-context: current!)
                                   (.o generation: generation-value source-dependencies: related))))
                   (unless (eq? id (.ref value 'identity))
                     (error "prepared publication source owner mismatch" id value))
                   (hash-put! prepared id value) value)))
           ((.ref value 'admit-current))
           (current!)
           value))))
    ;; Slot caching belongs to this immutable generation. Consumers must call
    ;; admit-current before publishing/using a Graph; cached slots are not live IO.
    (.o generation: generation-value
        context: context-value
        admit-current: current!
        prepare-publication: prepare
        modules:
        (let (resolve-scope (lambda (id) (.ref (resolve id) 'scope)))
          (or (and (.slot? context-value 'namespace)
                   ((.ref context-value 'namespace) resolve-scope))
              (scope-tree (map (lambda (id) (cons (module-id-parts id) id))
                               (.ref context-value 'selected)) resolve-scope)))
        ;; This immutable snapshot has exactly the init roots. Auto namespace
        ;; reads admit an additional bounded demand; they do not rewrite init.
        build-graph: (module-build-graph selected-graph prepare)
        selected-graph: (resolve-selection-graph (.ref context-value 'selected))
        selected-records: (begin (resolve-selection-graph (.ref context-value 'selected))
                                 (map resolve (.ref context-value 'selected)))
        dependency-order:
        (.ref (resolve-selection-graph (.ref context-value 'selected)) 'module-order))))
