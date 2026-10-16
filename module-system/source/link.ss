;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generation-local linking over admitted source capabilities. No filesystem backend.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .ref .all-slots object<-alist object<-fun)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        :core/module-system/source/objects
        :core/module-system/source/publication)
(export poo-flow-load-modules)
(def (admit-module-value! contract candidate context-value)
  (let (evidence (poo-flow-contract-admit contract candidate context-value))
    (unless (poo-flow-validation-evidence-accepted? evidence)
      (error "module scope admission refused" (.ref contract 'identity) evidence))
    evidence))
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
(def (poo-flow-load-modules context-value)
  (admit-module-value! ModuleScopeContextContract context-value context-value)
  (let ((cache (make-hash-table))
        (active (make-hash-table))
        (order '())
        (failed? #f)
        (generation-value (.ref context-value 'generation)))
    (def (current!)
      (when failed? (error "module scope session was refused" generation-value))
      (unless ((.ref context-value 'current?) generation-value)
        (set! failed? #t)
        (error "stale module scope generation" generation-value)))
    (def (link id path)
      (current!)
      (when (memq id (.ref context-value 'denied-modules))
        (error "required module disabled" (reverse (cons id path))))
      (unless (memq id (.ref context-value 'module-ids))
        (error "module is outside selected source-value policy" (reverse (cons id path))))
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
                   (admit-module-value! ModulePublicationContract publication-value context-value)))
             (unless (eq? id (.ref publication-value 'identity))
               (error "publication source owner mismatch" id source-value))
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
    ;; Slot caching belongs to this immutable generation. Consumers must call
    ;; admit-current before publishing/using a plan; cached slots are not live IO.
    (.o generation: generation-value
        context: context-value
        admit-current: current!
        modules:
        (scope-tree (map (lambda (id) (cons (module-id-parts id) id))
                         (.ref context-value 'selected))
                    (lambda (id) (.ref (resolve id) 'scope)))
        selected-records: (map resolve (.ref context-value 'selected))
        dependency-order:
        (begin (map resolve (.ref context-value 'selected)) (reverse order)))))
