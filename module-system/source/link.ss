;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generation-local linking over admitted source capabilities. The filesystem source adapter remains separate from runtime loading.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .ref .slot? .all-slots object<-alist object<-fun)
        :core/module-system/source/objects
        :core/module-system/source/publication
        :core/module-system/source/admission
        :core/module-system/source/preparation
        :core/module-system/source/directory)
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
   (if (string? source) (module-directory-context source publication-reader) source)))
(def (link-module-context context-value)
  (admit-module-value! ModuleScopeContextContract context-value context-value)
  (let ((cache (make-hash-table))
        (prepared (make-hash-table))
        (active (make-hash-table))
        (order '())
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
           (let* ((source-value ((.ref context-value 'locate) id))
                  (_source-admitted
                   (unless (poo-flow-module-source-ref? source-value)
                     (error "module scope requires an admitted SourceRef" id source-value)))
                  (publication-value ((.ref context-value 'read-publication) source-value))
                  (publication-evidence-value
                   (admit-module-publication! source-value id publication-value context-value)))
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
               (set! order (cons id order))
               record)))
         (lambda () (hash-remove! active id))))))
    (def (resolve id)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda () (link id '()))))
    (def (prepare id)
      (with-catch
       (lambda (exception) (set! failed? #t) (raise exception))
       (lambda ()
         (eligible! id '())
         (let (value
               (if (hash-key? prepared id) (hash-ref prepared id)
                 (let (value (poo-flow-prepare-module-publication
                              ((.ref context-value 'locate) id)))
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
        selected-records: (map resolve (.ref context-value 'selected))
        dependency-order:
        (begin (map resolve (.ref context-value 'selected)) (reverse order)))))
