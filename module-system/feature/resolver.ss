;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: resolves feature-profile selections into deterministic feature sets.
;;; Invariant: dependency closure cannot introduce an undeclared feature identity.
(import (runtime: :clan/poo/object)
        (prefix-in :clan/poo/generalized-graph graph.)
        (prefix-in :clan/poo/strong-components scc.)
        (only-in :clan/poo/dependency-analysis Computation.)
        :tao3k/yuanxu/module-system/feature/model
        :tao3k/yuanxu/utilities/functional)

(export resolve-feature-profile)

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

(def (topological-feature-selections keys index)
  ;; Admission owns the payload index; POO owns the structural schedule.
  ;; One row per accepted selection, with no Feature payload evaluation.
  (def codes
    (filter-map
      (lambda (key)
        (let (reads (selected-dependencies (selection-descriptor (hash-ref index key)) index))
          (and (pair? reads) (cons key (.cc Computation. reads: reads)))))
      keys))
  (def scheduled
    (with-catch
      (lambda (cause)
        (if (and (graph.failure? cause) (eq? (graph.failure-kind cause) 'cycle))
          #f
          (raise cause)))
      (lambda () (graph.schedule-owned keys codes))))
  (if scheduled
    (values (map (cut hash-ref index <>) (graph.schedule-order scheduled)) '())
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
