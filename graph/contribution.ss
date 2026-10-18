;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Graph contribution and ordered-application receipt values; payload helpers.

(import (only-in :clan/poo/object
                 .o
                 .ref
                 object?)
)

(import :core/graph/rooted)

(export (import: :core/graph/rooted)
        poo-flow-graph-operation-kind
        poo-flow-graph-contribution-kind
        poo-flow-graph-result-kind
        poo-flow-graph-kind?
        poo-flow-graph-operation-action
        poo-flow-graph-operation-slot
        poo-flow-graph-operation-value
        poo-flow-graph-operation-node
        poo-flow-graph-operation-target
        poo-flow-graph-contribution
        poo-flow-graph-contribution?
        poo-flow-graph-contribution-target
        poo-flow-graph-contribution-operations
        poo-flow-graph-result
        poo-flow-graph-result?
        poo-flow-graph-result-root
        poo-flow-graph-result-changed-passes
        poo-flow-graph-result-applied?
        poo-flow-graph-member?
        poo-flow-graph-value-index
        poo-flow-graph-append-distinct
        poo-flow-graph-append-distinct/indexed
        poo-flow-graph-remove-elements
        poo-flow-graph-list-value
        poo-flow-graph-entry-key
        poo-flow-graph-entry-value
        poo-flow-graph-entry
        poo-flow-graph-alist-set
        poo-flow-graph-alist-ref/default
)


;; : PooGraphOperationKindId
;; | PooGraphOperationKindId = String
(def poo-flow-graph-operation-kind "poo-flow.graph.operation.v1")
;; : PooGraphContributionKindId
;; | PooGraphContributionKindId = String
(def poo-flow-graph-contribution-kind "poo-flow.graph.contribution.v1")
;; : PooGraphResultKindId
;; | PooGraphResultKindId = String
(def poo-flow-graph-result-kind "poo-flow.graph.result.v1")

;;; Kind checks are slot-based so POO extension objects can evolve without
;;; exposing constructor identity to downstream module configs.
;; : (-> PooModuleValueCandidate PooModuleKindId Boolean)
(def (poo-flow-graph-kind? value kind)
  (and (object? value) (equal? (.ref value 'kind) kind)))

;; : (-> PooGraphOperation Symbol)
(def (poo-flow-graph-operation-action operation) (.ref operation 'action))
;; : (-> PooGraphOperation MaybeSymbol)
(def (poo-flow-graph-operation-slot operation) (.ref operation 'slot))
;; : (-> PooGraphOperation PooModuleSlotValue)
(def (poo-flow-graph-operation-value operation) (.ref operation 'value))
;; : (-> PooGraphOperation MaybePooFlowGraph)
(def (poo-flow-graph-operation-node operation) (.ref operation 'node))
;; : (-> PooGraphOperation MaybeSymbol)
(def (poo-flow-graph-operation-target operation) (.ref operation 'target))

;;; Contributions keep the target identity outside individual operations so a
;;; profile can patch one node with several ordered edits.
;; : (-> Symbol [PooGraphOperation] PooGraphContribution)
(def (poo-flow-graph-contribution target operations)
  (let ((target-value target) (operations-value operations))
    (.o kind: poo-flow-graph-contribution-kind
        target: target-value
        operations: operations-value)))

;; : (-> PooGraphContributionCandidate Boolean)
(def (poo-flow-graph-contribution? value)
  (poo-flow-graph-kind? value poo-flow-graph-contribution-kind))
;; : (-> PooGraphContribution Symbol)
(def (poo-flow-graph-contribution-target contribution) (.ref contribution 'target))
;; : (-> PooGraphContribution [PooGraphOperation])
(def (poo-flow-graph-contribution-operations contribution) (.ref contribution 'operations))

;;; Ordered application receipt. changed-passes is 0 or 1; applied? records
;;; completion of this pass and makes no fixed-point or convergence claim.
;; : (-> PooFlowGraph Integer Boolean PooGraphResult)
(def (poo-flow-graph-result root changed-passes applied?)
  (let ((root-value root) (passes-value changed-passes) (applied-value applied?))
    (.o kind: poo-flow-graph-result-kind
        root: root-value
        changed-passes: passes-value
        applied?: applied-value)))

;; : (-> PooModuleResultCandidate Boolean)
(def (poo-flow-graph-result? value)
  (poo-flow-graph-kind? value poo-flow-graph-result-kind))
;; : (-> PooGraphResult PooFlowGraph)
(def (poo-flow-graph-result-root result) (.ref result 'root))
;; : (-> PooGraphResult Integer)
(def (poo-flow-graph-result-changed-passes result) (.ref result 'changed-passes))
;; : (-> PooGraphResult Boolean)
(def (poo-flow-graph-result-applied? result) (.ref result 'applied?))

;; : (-> PooModuleSlotValue [PooModuleSlotValue] Boolean)
(def (poo-flow-graph-member? value values)
  (and (member value values) #t))

;;; Boundary: module extension value index is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> [PooModuleSlotValue] HashTable)
(def (poo-flow-graph-value-index values)
  (let (index (make-hash-table))
    (for-each
     (lambda (value)
       (hash-put! index value #t))
     values)
    index))

;;; Append keeps the base order stable and filters only duplicate extras, which
;;; makes agent-authored list extensions deterministic under repeated demand.
;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (poo-flow-graph-append-distinct base extra)
  (if (null? extra)
    base
    (poo-flow-graph-append-distinct/indexed
     base
     extra
     (poo-flow-graph-value-index base))))

;;; Boundary: module extension append distinct indexed is the policy-visible
;;; edge for module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> [PooModuleSlotValue] HashTable [PooModuleSlotValue] [PooModuleSlotValue])
(def (poo-flow-graph-append-distinct-added/rev
      extra
      seen
      added-rev)
  (append
   (reverse
    (filter-map
     (lambda (value)
       (and (not (hash-get seen value))
            (begin
              (hash-put! seen value #t)
              value)))
     extra))
   added-rev))

;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] HashTable [PooModuleSlotValue])
(def (poo-flow-graph-append-distinct/indexed base extra seen)
  (let (added
        (poo-flow-graph-append-distinct-added/rev
         extra
         seen
         '()))
    (if (null? added)
      base
      (append base (reverse added)))))

;;; Remove is value-based rather than positional so downstream patches can
;;; delete inherited list elements without knowing the upstream list index.
;; : (-> [PooModuleSlotValue] HashTable [PooModuleSlotValue] [PooModuleSlotValue])
(def (poo-flow-graph-remove-elements/rev values removed-index kept-rev)
  (cond
   ((null? values) kept-rev)
   ((hash-get removed-index (car values))
    (poo-flow-graph-remove-elements/rev
     (cdr values)
     removed-index
     kept-rev))
   (else
    (poo-flow-graph-remove-elements/rev
     (cdr values)
     removed-index
     (cons (car values) kept-rev)))))

;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (poo-flow-graph-remove-elements values removed)
  (if (null? removed)
    values
    (let (removed-index (poo-flow-graph-value-index removed))
      (filter (lambda (value)
                (not (hash-get removed-index value)))
              values))))

;;; Boundary: module extension list value is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> PooModuleSlotValue [PooModuleSlotValue])
(def (poo-flow-graph-list-value value)
  (cond ((null? value) '())
        ((list? value) value)
        (else (list value))))

;; : (-> PooModuleSlotEntry Symbol)
(def (poo-flow-graph-entry-key entry)
  (car entry))

;; : (-> PooModuleSlotEntry PooModuleSlotValue)
(def (poo-flow-graph-entry-value entry)
  (cdr entry))

;; : (-> Symbol PooModuleSlotValue PooModuleSlotEntry)
(def (poo-flow-graph-entry key value)
  (cons key value))

;;; Boundary: module extension alist set is the policy-visible edge for module-
;;; system behavior, keeping validation, lookup, or projection responsibilities
;;; centralized for callers.
;; : (-> PooModuleSlotMap Symbol PooModuleSlotValue PooModuleSlotMap)
(def (poo-flow-graph-alist-set entries key value)
  (cond ((null? entries)
         (list (poo-flow-graph-entry key value)))
        ((equal? (poo-flow-graph-entry-key (car entries)) key)
         (cons (poo-flow-graph-entry key value)
               (cdr entries)))
        (else (cons (car entries)
                    (poo-flow-graph-alist-set (cdr entries) key value)))))

;;; Boundary: module extension alist ref default is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> PooModuleSlotMap Symbol PooModuleSlotValue PooModuleSlotValue)
(def (poo-flow-graph-alist-ref/default entries key default-value)
  (let (entry (assoc key entries))
    (if entry (cdr entry) default-value)))

;; poo-flow-graph-slots-merge
;;   : (-> PooModuleSlotMap PooModuleSlotMap PooModuleSlotMap)
;;   | doc m%
;;       `poo-flow-graph-slots-merge base extra` overlays slot
;;       values from `extra` while preserving the first-seen slot order from
;;       `base`; new slot keys are appended in first override order.
;;
;;       # Examples
;;       ```scheme
;;       (poo-flow-graph-slots-merge
;;        '((mode . dev) (features . (base)))
;;        '((mode . prod) (extra . #t)))
;;       ;; => ((mode . prod) (features base) (extra . #t))
;;       ```
;;     %
