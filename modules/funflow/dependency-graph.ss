;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: indexed dependency analysis for workflow CI/CD checks.
;;; Invariant: graph algorithms emit report facts and never schedule commands.

(import (only-in :clan/poo/object .ref)
        (only-in :std/hash/misc hash-ensure-modify!)
        (only-in :std/struct/queue dequeue! enqueue! make-Queue queue-empty?)
        (only-in :yuanxu/graph/types-core
                 yuanxu-graph
                 yuanxu-graph-edge
                 yuanxu-graph-node)
        (only-in :yuanxu/graph/algorithms
                 yuanxu-graph-loop-analysis-receipt)
        (only-in :yuanxu/utilities/functional
                 yuanxu-filter-map
                 yuanxu-stable-duplicates)
        :yuanxu/modules/funflow/check-types
        :yuanxu/modules/funflow/check-objects
        :yuanxu/modules/funflow/projection-syntax)

(export yuanxu-cicd-check-map->dependency-graph)

(defstruct yuanxu-cicd-graph-index
  (node-names node-index dependents indegrees edges unresolved-rev)
  transparent: #t)

(def (yuanxu-cicd-checks-names checks)
  (map yuanxu-cicd-check-name checks))

(def (yuanxu-cicd-index-checks checks)
  (let ((node-names (yuanxu-cicd-checks-names checks))
        (node-index (make-hash-table-eq))
        (dependents (make-hash-table-eq))
        (indegrees (make-hash-table-eq)))
    (for-each
     (lambda (check)
       (let (name (yuanxu-cicd-check-name check))
         ;; First-match ownership stays deterministic when duplicate names are
         ;; later reported as invalid graph input.
         (unless (hash-key? node-index name) (hash-put! node-index name #t))
         (hash-put! indegrees name 0)))
     checks)
    (let ((edges-rev '()) (unresolved-rev '()))
      (for-each
       (lambda (check)
         (let (target (yuanxu-cicd-check-name check))
           (for-each
            (lambda (source)
              (set! edges-rev (cons (cons source target) edges-rev))
              ;; Missing sources still block the target.  They are diagnosed
              ;; below and deliberately have no dependent frontier to release.
              (hash-put! indegrees target (+ 1 (hash-get indegrees target)))
              (if (hash-key? node-index source)
                (begin
                  (hash-ensure-modify!
                   dependents source (lambda () '())
                   (lambda (values) (cons target values))))
                (set! unresolved-rev (cons source unresolved-rev))))
            (yuanxu-cicd-check-dependency-refs check))))
       checks)
      (make-yuanxu-cicd-graph-index
       node-names node-index dependents indegrees
       (reverse edges-rev) unresolved-rev))))

(def (yuanxu-cicd-index-ready-order index)
  (let ((pending (make-Queue))
        (indegrees (yuanxu-cicd-graph-index-indegrees index))
        (dependents (yuanxu-cicd-graph-index-dependents index)))
    (for-each
     (lambda (name)
       (when (zero? (hash-get indegrees name)) (enqueue! pending name)))
     (yuanxu-cicd-graph-index-node-names index))
    (let loop ((order-rev '()))
      (if (queue-empty? pending)
        (reverse order-rev)
        (let (name (dequeue! pending))
          (for-each
           (lambda (dependent)
             (let (next (- (hash-get indegrees dependent) 1))
               (hash-put! indegrees dependent next)
               (when (zero? next) (enqueue! pending dependent))))
           ;; Edges were indexed by cons; one reverse restores declaration order.
           (reverse (or (hash-get dependents name) '())))
          (loop (cons name order-rev)))))))

(def (yuanxu-cicd-index-generic-graph check-map index)
  (let ((node-index (yuanxu-cicd-graph-index-node-index index)))
    (yuanxu-graph
     (yuanxu-cicd-check-map-name check-map)
     (map (lambda (name) (yuanxu-graph-node name))
          (yuanxu-cicd-graph-index-node-names index))
     (yuanxu-filter-map
      (lambda (edge)
        (and (hash-key? node-index (car edge))
             (yuanxu-graph-edge (car edge) (cdr edge))))
      (yuanxu-cicd-graph-index-edges index)))))

(def (yuanxu-cicd-index-cycle-nodes check-map index)
  (let* ((analysis
          (yuanxu-graph-loop-analysis-receipt
           (yuanxu-cicd-index-generic-graph check-map index)))
         (cycle-index (make-hash-table-eq)))
    (for-each
     (lambda (component)
       (for-each (lambda (name) (hash-put! cycle-index name #t)) component))
     (.ref analysis 'cyclic-components))
    (yuanxu-filter-map
     (lambda (name) (and (hash-key? cycle-index name) name))
     (yuanxu-cicd-graph-index-node-names index))))

(def (yuanxu-cicd-index-edge-rows index)
  (map (lambda (edge)
         (yuanxu-cicd-field-rows (from (car edge)) (to (cdr edge))))
       (yuanxu-cicd-graph-index-edges index)))

(def (yuanxu-cicd-index-unordered-nodes index ready-order)
  (let (ready-index (make-hash-table-eq))
    (for-each (lambda (name) (hash-put! ready-index name #t)) ready-order)
    (yuanxu-filter-map
     (lambda (name) (and (not (hash-key? ready-index name)) name))
     (yuanxu-cicd-graph-index-node-names index))))

(def (yuanxu-cicd-dependency-graph-diagnostics duplicate-nodes unresolved cycle-nodes)
  (yuanxu-filter-map
   (lambda (row) (and (pair? (car row)) (cdr row)))
   (list (cons duplicate-nodes 'duplicate-nodes)
         (cons unresolved 'unresolved-dependency-refs)
         (cons cycle-nodes 'cycle-detected))))

(def (yuanxu-cicd-check-map->dependency-graph check-map)
  (yuanxu-cicd-require "cicd dependency graph requires a cicd check-map"
                         (yuanxu-cicd-check-map? check-map) check-map)
  (let* ((checks (yuanxu-cicd-check-map-checks check-map))
         (index (yuanxu-cicd-index-checks checks))
         (node-names (yuanxu-cicd-graph-index-node-names index))
         (duplicate-nodes (yuanxu-stable-duplicates node-names))
         (unresolved (reverse (yuanxu-cicd-graph-index-unresolved-rev index)))
         (cycle-nodes
          (if (null? duplicate-nodes)
            (yuanxu-cicd-index-cycle-nodes check-map index)
            '()))
         (diagnostics
          (yuanxu-cicd-dependency-graph-diagnostics
           duplicate-nodes unresolved cycle-nodes))
         (ready-order
          (if (null? duplicate-nodes)
            (yuanxu-cicd-index-ready-order index)
            '()))
         (unordered (yuanxu-cicd-index-unordered-nodes index ready-order)))
    (yuanxu-cicd-field-rows
     (kind 'yuanxu.workflow.cicd.dependency-graph)
     (check-map (yuanxu-cicd-check-map-name check-map))
     (order-policy 'declaration-topological-report)
     (nodes node-names)
     (duplicate-nodes duplicate-nodes)
     (edges (yuanxu-cicd-index-edge-rows index))
     (unresolved-dependency-refs unresolved)
     (cycle-nodes cycle-nodes)
     (ready-order ready-order)
     (unordered-nodes unordered)
     (blocked-order? (or (pair? diagnostics)
                         (not (= (length ready-order) (length node-names)))))
     (diagnostics diagnostics)
     (valid? (null? diagnostics))
     (runtime-executed #f))))
