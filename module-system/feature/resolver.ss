;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: resolves feature-profile selections into deterministic feature sets.
;;; Invariant: dependency closure cannot introduce an undeclared feature identity.
(import (runtime: :clan/poo/object)
        (prefix-in :clan/poo/graph/schedule graph.)
        (prefix-in :clan/poo/graph/scc scc.)
        (only-in :clan/poo/graph/computation Computation.)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-measure-operation)
        :tao3k/yuanxu/module-system/feature/model
        :tao3k/yuanxu/utilities/functional)

(export resolve-feature-profile schedule-core-rows)

(def (selection-id selection)
  (.ref selection 'feature-id))

(def (selection-descriptor selection)
  (.ref selection 'descriptor))

(def (index-feature-selections selections)
  (def index (make-hash-table-eq))
  (def keys '())
  (def diagnostics '())
  (for-each
    (lambda (selection)
      (let (id (selection-id selection))
        (if (hash-key? index id)
          (set! diagnostics (cons (feature-diagnostic 'duplicate-selection id id #f) diagnostics))
          (begin
            (hash-put! index id selection)
            (set! keys (cons id keys))))))
    selections)
  (values index (reverse keys) (reverse diagnostics)))

(def (missing-dependency-diagnostics selections index)
  (foldr
   (lambda (selection diagnostics)
     (let* ((descriptor (selection-descriptor selection))
            (feature-id (selection-id selection)))
       (append
        (filter-map
         (lambda (required-id)
           (and (not (hash-key? index required-id))
                (feature-diagnostic
                 'missing-dependency feature-id required-id #f)))
         (.ref descriptor 'requires))
        diagnostics)))
   '()
   selections))

(def (conflict-diagnostics selections index)
  (foldr
   (lambda (selection diagnostics)
     (let* ((descriptor (selection-descriptor selection))
            (feature-id (selection-id selection)))
       (append
        (filter-map
         (lambda (conflict-id)
           (and (hash-key? index conflict-id)
                (feature-diagnostic
                 'feature-conflict feature-id conflict-id #f)))
         (.ref descriptor 'conflicts))
        diagnostics)))
   '()
   selections))

(def (selected-dependencies descriptor index)
  (append
   (filter-map
    (lambda (required-id)
      (and (hash-key? index required-id) required-id))
    (.ref descriptor 'requires))
   (filter-map
    (lambda (optional-id)
      (and (hash-key? index optional-id) optional-id))
    (.ref descriptor 'optional-requires))))

(def (schedule-feature-ids keys codes)
  (def scheduled
    (with-catch
      (lambda (cause)
        (if (and (graph.failure? cause) (eq? (graph.failure-kind cause) 'cycle))
          #f
          (raise cause)))
      (lambda ()
        (module-source-measure-operation 'selected-poo-schedule
          (lambda () (graph.schedule-owned keys codes))))))
  (if scheduled
    (values (graph.schedule-order scheduled) '())
    ;; An invalid graph has no execution order. Use the same captured rows
    ;; for POO's compact SCC diagnostics; do not reread authored slots.
    (let (partition (scc.partition (graph.declaration keys codes)))
      (values '()
        (filter-map
          (lambda (group)
            (let (key (car group))
              (and (or (pair? (cdr group)) (memq key ((scc.partition-reads partition) key)))
                   (feature-diagnostic 'dependency-cycle key key group))))
          (scc.partition-groups partition))))))

(def (dependency-code key reads)
  (and (pair? reads) (cons key (.cc Computation. reads: reads))))

(def (topological-feature-selections keys index)
  (def codes
    (filter-map
      (lambda (key)
        (dependency-code key (selected-dependencies (selection-descriptor (hash-ref index key)) index)))
      keys))
  (let-values (((ordered diagnostics) (schedule-feature-ids keys codes)))
    (values (map (cut hash-ref index <>) ordered) diagnostics)))

(def (schedule-core-rows rows)
  ;; The admitted owner closure supplies distinct keys and all required owners.
  ;; Core has no optional edges or conflicts.
  (schedule-feature-ids (map car rows)
    (filter-map (lambda (row) (dependency-code (car row) (cdr row))) rows)))

(def (resolve-feature-profile profile)
  (let ((selections (.ref profile 'selections)))
    (let-values (((index keys duplicate-diagnostics)
                  (index-feature-selections selections)))
      (let-values (((ordered cycle-diagnostics)
                    (topological-feature-selections keys index)))
        (let* ((diagnostics
                (append
                 duplicate-diagnostics
                 (missing-dependency-diagnostics selections index)
                 (conflict-diagnostics selections index)
                 cycle-diagnostics))
               (status (if (null? diagnostics) 'ready 'rejected)))
          (feature-activation-plan
           profile
           status
           ordered
           (map selection-id ordered)
           diagnostics))))))
