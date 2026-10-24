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

(import :yuanxu/graph/rooted)

(export (import: :yuanxu/graph/rooted)
        yuanxu-graph-operation-kind
        yuanxu-graph-contribution-kind
        yuanxu-graph-result-kind
        yuanxu-graph-kind?
        yuanxu-graph-operation-action
        yuanxu-graph-operation-slot
        yuanxu-graph-operation-value
        yuanxu-graph-operation-node
        yuanxu-graph-operation-target
        yuanxu-graph-contribution
        yuanxu-graph-contribution?
        yuanxu-graph-contribution-target
        yuanxu-graph-contribution-operations
        yuanxu-graph-result
        yuanxu-graph-result?
        yuanxu-graph-result-root
        yuanxu-graph-result-changed-passes
        yuanxu-graph-result-applied?
        yuanxu-graph-member?
        yuanxu-graph-value-index
        yuanxu-graph-append-distinct
        yuanxu-graph-append-distinct/indexed
        yuanxu-graph-remove-elements
        yuanxu-graph-list-value
        yuanxu-graph-entry-key
        yuanxu-graph-entry-value
        yuanxu-graph-entry
        yuanxu-graph-alist-set
        yuanxu-graph-alist-ref/default
)


;; : PooGraphOperationKindId
;; | PooGraphOperationKindId = String
(def yuanxu-graph-operation-kind "yuanxu.graph.operation.v1")
;; : PooGraphContributionKindId
;; | PooGraphContributionKindId = String
(def yuanxu-graph-contribution-kind "yuanxu.graph.contribution.v1")
;; : PooGraphResultKindId
;; | PooGraphResultKindId = String
(def yuanxu-graph-result-kind "yuanxu.graph.result.v1")

;;; Kind checks are slot-based so POO extension objects can evolve without
;;; exposing constructor identity to downstream module configs.
;; : (-> PooModuleValueCandidate PooModuleKindId Boolean)
(def (yuanxu-graph-kind? value kind)
  (and (object? value) (equal? (.ref value 'kind) kind)))

;; : (-> PooGraphOperation Symbol)
(def (yuanxu-graph-operation-action operation) (.ref operation 'action))
;; : (-> PooGraphOperation MaybeSymbol)
(def (yuanxu-graph-operation-slot operation) (.ref operation 'slot))
;; : (-> PooGraphOperation PooModuleSlotValue)
(def (yuanxu-graph-operation-value operation) (.ref operation 'value))
;; : (-> PooGraphOperation MaybeYuanxuGraph)
(def (yuanxu-graph-operation-node operation) (.ref operation 'node))
;; : (-> PooGraphOperation MaybeSymbol)
(def (yuanxu-graph-operation-target operation) (.ref operation 'target))

;;; Contributions keep the target identity outside individual operations so a
;;; profile can patch one node with several ordered edits.
;; : (-> Symbol [PooGraphOperation] PooGraphContribution)
(def (yuanxu-graph-contribution target operations)
  (let ((target-value target) (operations-value operations))
    (.o kind: yuanxu-graph-contribution-kind
        target: target-value
        operations: operations-value)))

;; : (-> PooGraphContributionCandidate Boolean)
(def (yuanxu-graph-contribution? value)
  (yuanxu-graph-kind? value yuanxu-graph-contribution-kind))
;; : (-> PooGraphContribution Symbol)
(def (yuanxu-graph-contribution-target contribution) (.ref contribution 'target))
;; : (-> PooGraphContribution [PooGraphOperation])
(def (yuanxu-graph-contribution-operations contribution) (.ref contribution 'operations))

;;; Ordered application receipt. changed-passes is 0 or 1; applied? records
;;; completion of this pass and makes no fixed-point or convergence claim.
;; : (-> YuanxuGraph Integer Boolean PooGraphResult)
(def (yuanxu-graph-result root changed-passes applied?)
  (let ((root-value root) (passes-value changed-passes) (applied-value applied?))
    (.o kind: yuanxu-graph-result-kind
        root: root-value
        changed-passes: passes-value
        applied?: applied-value)))

;; : (-> PooModuleResultCandidate Boolean)
(def (yuanxu-graph-result? value)
  (yuanxu-graph-kind? value yuanxu-graph-result-kind))
;; : (-> PooGraphResult YuanxuGraph)
(def (yuanxu-graph-result-root result) (.ref result 'root))
;; : (-> PooGraphResult Integer)
(def (yuanxu-graph-result-changed-passes result) (.ref result 'changed-passes))
;; : (-> PooGraphResult Boolean)
(def (yuanxu-graph-result-applied? result) (.ref result 'applied?))

;; : (-> PooModuleSlotValue [PooModuleSlotValue] Boolean)
(def (yuanxu-graph-member? value values)
  (and (member value values) #t))

;;; Boundary: module extension value index is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> [PooModuleSlotValue] HashTable)
(def (yuanxu-graph-value-index values)
  (let (index (make-hash-table))
    (for-each
     (lambda (value)
       (hash-put! index value #t))
     values)
    index))

;;; Append keeps the base order stable and filters only duplicate extras, which
;;; makes agent-authored list extensions deterministic under repeated demand.
;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-graph-append-distinct base extra)
  (if (null? extra)
    base
    (yuanxu-graph-append-distinct/indexed
     base
     extra
     (yuanxu-graph-value-index base))))

;;; Boundary: module extension append distinct indexed is the policy-visible
;;; edge for module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> [PooModuleSlotValue] HashTable [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-graph-append-distinct-added/rev
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
(def (yuanxu-graph-append-distinct/indexed base extra seen)
  (let (added
        (yuanxu-graph-append-distinct-added/rev
         extra
         seen
         '()))
    (if (null? added)
      base
      (append base (reverse added)))))

;;; Remove is value-based rather than positional so downstream patches can
;;; delete inherited list elements without knowing the upstream list index.
;; : (-> [PooModuleSlotValue] HashTable [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-graph-remove-elements/rev values removed-index kept-rev)
  (cond
   ((null? values) kept-rev)
   ((hash-get removed-index (car values))
    (yuanxu-graph-remove-elements/rev
     (cdr values)
     removed-index
     kept-rev))
   (else
    (yuanxu-graph-remove-elements/rev
     (cdr values)
     removed-index
     (cons (car values) kept-rev)))))

;; : (-> [PooModuleSlotValue] [PooModuleSlotValue] [PooModuleSlotValue])
(def (yuanxu-graph-remove-elements values removed)
  (if (null? removed)
    values
    (let (removed-index (yuanxu-graph-value-index removed))
      (filter (lambda (value)
                (not (hash-get removed-index value)))
              values))))

;;; Boundary: module extension list value is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> PooModuleSlotValue [PooModuleSlotValue])
(def (yuanxu-graph-list-value value)
  (cond ((null? value) '())
        ((list? value) value)
        (else (list value))))

;; : (-> PooModuleSlotEntry Symbol)
(def (yuanxu-graph-entry-key entry)
  (car entry))

;; : (-> PooModuleSlotEntry PooModuleSlotValue)
(def (yuanxu-graph-entry-value entry)
  (cdr entry))

;; : (-> Symbol PooModuleSlotValue PooModuleSlotEntry)
(def (yuanxu-graph-entry key value)
  (cons key value))

;;; Boundary: module extension alist set is the policy-visible edge for module-
;;; system behavior, keeping validation, lookup, or projection responsibilities
;;; centralized for callers.
;; : (-> PooModuleSlotMap Symbol PooModuleSlotValue PooModuleSlotMap)
(def (yuanxu-graph-alist-set entries key value)
  (cond ((null? entries)
         (list (yuanxu-graph-entry key value)))
        ((equal? (yuanxu-graph-entry-key (car entries)) key)
         (cons (yuanxu-graph-entry key value)
               (cdr entries)))
        (else (cons (car entries)
                    (yuanxu-graph-alist-set (cdr entries) key value)))))

;;; Boundary: module extension alist ref default is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> PooModuleSlotMap Symbol PooModuleSlotValue PooModuleSlotValue)
(def (yuanxu-graph-alist-ref/default entries key default-value)
  (let (entry (assoc key entries))
    (if entry (cdr entry) default-value)))

;; yuanxu-graph-slots-merge
;;   : (-> PooModuleSlotMap PooModuleSlotMap PooModuleSlotMap)
;;   | doc m%
;;       `yuanxu-graph-slots-merge base extra` overlays slot
;;       values from `extra` while preserving the first-seen slot order from
;;       `base`; new slot keys are appended in first override order.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-graph-slots-merge
;;        '((mode . dev) (features . (base)))
;;        '((mode . prod) (extra . #t)))
;;       ;; => ((mode . prod) (features base) (extra . #t))
;;       ```
;;     %
