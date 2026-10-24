;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: ordered field-contribution resolution for module object graphs.

(import :gerbil/core
        (only-in :clan/poo/object .o .ref)
        :yuanxu/graph/interface
        :yuanxu/module-system/schema/support/contracts
        :yuanxu/module-system/schema/support/slot-policy)

(export yuanxu-module-field-resolution-result
        yuanxu-module-field-resolution-result?
        yuanxu-module-field-resolution-result-extension-result
        yuanxu-module-field-resolution-result-contributions
        yuanxu-module-field-resolution-result-root
        yuanxu-module-field-resolution-result-changed-passes
        yuanxu-module-field-resolution-result-applied?
        yuanxu-module-config-fast-slot-merge/in-order
        yuanxu-module-config-slot-key-hash-ref
        yuanxu-module-config-fast-slot-merge/sparse
        yuanxu-module-config-fast-slot-merge
        yuanxu-module-config-fast-extension-result
        yuanxu-module-field-contributions-resolve)


;;; Field resolution results preserve the original contributions so diagnostics can
;;; explain both the final graph and the inputs that produced it.
;; : (-> PooGraphResult [PooModuleFieldContribution] PooModuleFieldResolutionResult)
(def (yuanxu-module-field-resolution-result extension-result contributions)
  (let ((extension-result-value extension-result)
        (contributions-value contributions))
    (.o kind: yuanxu-module-field-resolution-result-kind
        extension-result: extension-result-value
        contributions: contributions-value)))

;; : (-> PooModuleFieldResolutionResultCandidate Boolean)
(def (yuanxu-module-field-resolution-result? value)
  (yuanxu-module-object-kind? value yuanxu-module-field-resolution-result-kind))

;; : (-> PooModuleFieldResolutionResult PooGraphResult)
(def (yuanxu-module-field-resolution-result-extension-result result)
  (.ref result 'extension-result))
;; : (-> PooModuleFieldResolutionResult [PooModuleFieldContribution])
(def (yuanxu-module-field-resolution-result-contributions result)
  (.ref result 'contributions))
;; : (-> PooModuleFieldResolutionResult YuanxuGraph)
(def (yuanxu-module-field-resolution-result-root result)
  (yuanxu-graph-result-root
   (yuanxu-module-field-resolution-result-extension-result result)))
;; : (-> PooModuleFieldResolutionResult Integer)
(def (yuanxu-module-field-resolution-result-changed-passes result)
  (yuanxu-graph-result-changed-passes
   (yuanxu-module-field-resolution-result-extension-result result)))
;; : (-> PooModuleFieldResolutionResult Boolean)
(def (yuanxu-module-field-resolution-result-applied? result)
  (yuanxu-graph-result-applied?
   (yuanxu-module-field-resolution-result-extension-result result)))

;; yuanxu-module-config-fast-slot-merge/in-order
;;   : (-> Symbol PooModuleSlotMap [PooModuleFieldContribution] MaybePooModuleSlotMap)
;;   | doc m%
;;       `yuanxu-module-config-fast-slot-merge/in-order` applies field
;;       contributions while preserving slot order and allocating only when a
;;       value actually changes.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-config-fast-slot-merge/in-order node slots fields)
;;       ;; => maybe-updated-slots
;;       ```
;;     %
(def (yuanxu-module-config-fast-slot-merge/in-order node-identity slots contributions)
  (let ((head '())
        (tail #f)
        (seen (make-hash-table)))
    ;; : (-> Any Any)
    (def (append-entry! entry)
      (let (cell (cons entry '()))
        (if tail
          (begin
            (set-cdr! tail cell)
            (set! tail cell))
          (begin
            (set! head cell)
            (set! tail cell)))))
    ;; : (-> Any Any)
    (def (copy-prefix! stop)
      (let copy ((remaining slots))
        (when (not (eq? remaining stop))
          (append-entry! (car remaining))
          (copy (cdr remaining)))))
    (let loop ((remaining-slots slots)
               (remaining-contributions contributions)
               (changed? #f))
      (cond
       ((null? remaining-slots)
        (if (null? remaining-contributions)
          (if changed?
            head
            slots)
          #f))
       ((null? remaining-contributions) #f)
       (else
        (let ((entry (car remaining-slots))
              (contribution (car remaining-contributions)))
          (if (not (yuanxu-module-field-contribution? contribution))
            #f
            (let* ((target
                    (yuanxu-module-field-contribution-target contribution))
                   (value
                    (yuanxu-module-field-contribution-value contribution))
                   (key
                    (yuanxu-module-field-contribution-field-identity
                     contribution))
                   (slot-key (car entry))
                   (merge
                    (yuanxu-module-field-contribution-merge contribution))
                   (value-type
                    (yuanxu-module-field-contribution-field-value-type
                     contribution))
                   (field-contract?
                    (yuanxu-module-field-contribution-field-contract?
                     contribution))
                   (valid?
                    (or (not field-contract?)
                        (yuanxu-module-value-type-accepts?
                         value-type
                         value))))
              (if (and (equal? target node-identity)
                       valid?
                       (yuanxu-module-slot-policy? merge)
                       (equal? key slot-key))
                (if (hash-get seen slot-key)
                  #f
                  (begin
                    (hash-put! seen slot-key #t)
                    (let* ((current (cdr entry))
                           (next-value
                            (yuanxu-module-slot-apply-policy
                             merge
                             current
                             value))
                           (value-changed?
                            (not (or (eq? next-value current)
                                     (equal? next-value current)))))
                      (when (and value-changed? (not changed?))
                        (copy-prefix! remaining-slots))
                      (when (or changed? value-changed?)
                        (append-entry! (if value-changed?
                                         (cons key next-value)
                                         entry)))
                      (loop (cdr remaining-slots)
                            (cdr remaining-contributions)
                            (or changed? value-changed?)))))
                #f)))))))))

;; : (-> HashTable Symbol Value)
(def (yuanxu-module-config-slot-key-hash-ref table key)
  (hash-get table key))

;; yuanxu-module-config-fast-slot-merge/sparse
;;   : (-> Symbol PooModuleSlotMap [PooModuleFieldContribution] MaybePooModuleSlotMap)
;;   | doc m%
;;       `yuanxu-module-config-fast-slot-merge/sparse` handles sparse or
;;       repeated slot updates with hash-indexed state while keeping append and
;;       remove semantics equivalent to the ordered merge path.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-config-fast-slot-merge/sparse node slots fields)
;;       ;; => maybe-updated-slots
;;       ```
;;     %
(def (yuanxu-module-config-fast-slot-merge/sparse node-identity slots contributions)
  (let ((seen (make-hash-table))
        (updated (make-hash-table))
        (updates (make-hash-table))
        (value-indexes (make-hash-table))
        (append-active (make-hash-table))
        (append-bases (make-hash-table))
        (append-additions (make-hash-table)))
    ;; : (-> Any Any)
    (def (slot-value-index key current)
      (let (index (yuanxu-module-config-slot-key-hash-ref value-indexes key))
        (if index
          index
          (let (next-index
                (yuanxu-module-slot-value-index
                 (yuanxu-module-slot-list-value current)))
            (hash-put! value-indexes key next-index)
            next-index))))
    ;; : (-> Any Any)
    (def (record-slot-value-index! key value)
      (hash-put! value-indexes
                 key
                 (yuanxu-module-slot-value-index
                  (yuanxu-module-slot-list-value value))))
    ;; : (-> Any Any)
    (def (materialize-append-state key)
      (let ((base (yuanxu-module-config-slot-key-hash-ref
                   append-bases
                   key))
            (additions (yuanxu-module-config-slot-key-hash-ref
                        append-additions
                        key)))
        (if (null? additions)
          base
          (append base (reverse additions)))))
    ;; : (-> Any Any)
    (def (flush-append-state! key)
      (if (yuanxu-module-config-slot-key-hash-ref append-active key)
        (let (value (materialize-append-state key))
          (hash-put! updates key value)
          (hash-put! append-active key #f)
          (record-slot-value-index! key value)
          value)
        (yuanxu-module-config-slot-key-hash-ref updates key)))
    ;; : (-> Any Any)
    (def (resolved-slot-update key)
      (if (yuanxu-module-config-slot-key-hash-ref append-active key)
        (flush-append-state! key)
        (yuanxu-module-config-slot-key-hash-ref updates key)))
    ;; : (-> Any Any)
    (def (append-slot-value! key current value)
      (let ((current-list (yuanxu-module-slot-list-value current))
            (extra (yuanxu-module-slot-list-value value))
            (active? (yuanxu-module-config-slot-key-hash-ref
                      append-active
                      key)))
        (when (not active?)
          (hash-put! append-active key #t)
          (hash-put! append-bases key current-list)
          (hash-put! append-additions key '())
          (hash-put! updates key current-list))
        (let (seen-values (slot-value-index key current-list))
          (let loop ((remaining extra)
                     (additions
                      (yuanxu-module-config-slot-key-hash-ref
                       append-additions
                       key))
                     (changed? #f))
            (cond
             ((null? remaining)
              (hash-put! append-additions key additions)
              changed?)
             ((hash-get seen-values (car remaining))
              (loop (cdr remaining) additions changed?))
            (else
             (hash-put! seen-values (car remaining) #t)
             (loop (cdr remaining)
                    (cons (car remaining) additions)
                    #t)))))))
    ;; : (-> Any Any)
    (def (materialize-existing-slots/rev remaining rows-rev)
      (if (null? remaining)
        rows-rev
        (let (key (car (car remaining)))
          (materialize-existing-slots/rev
           (cdr remaining)
           (cons (if (yuanxu-module-config-slot-key-hash-ref updated key)
                   (cons key (resolved-slot-update key))
                   (car remaining))
                 rows-rev)))))
    ;; : (-> Any Any)
    (def (materialize-new-slots/rev keys rows-rev)
      (if (null? keys)
        rows-rev
        (materialize-new-slots/rev
         (cdr keys)
         (cons (cons (car keys) (resolved-slot-update (car keys)))
               rows-rev))))
    ;; : (-> Any Any)
    (def (materialize-updated-slots new-order)
      (reverse
       (materialize-new-slots/rev
        (reverse new-order)
        (materialize-existing-slots/rev slots '()))))
    (let init ((remaining slots))
      (cond
       ((null? remaining)
        (let apply-contributions ((rest contributions)
                                  (new-order '())
                                  (changed? #f))
          (if (null? rest)
            (if (and (not changed?) (null? new-order))
              slots
              (materialize-updated-slots new-order))
            (let* ((contribution (car rest))
                   (target
                    (yuanxu-module-field-contribution-target contribution))
                   (value
                    (yuanxu-module-field-contribution-value contribution))
                   (field-contract?
                    (yuanxu-module-field-contribution-field-contract?
                     contribution))
                   (valid?
                    (or (not field-contract?)
                        (yuanxu-module-value-type-accepts?
                         (yuanxu-module-field-contribution-field-value-type
                          contribution)
                         value)))
                   (key
                    (yuanxu-module-field-contribution-field-identity
                     contribution))
                   (merge
                    (yuanxu-module-field-contribution-merge contribution)))
              (if (and (equal? target node-identity)
                       valid?
                       (yuanxu-module-slot-policy? merge))
                (let* ((entry (yuanxu-module-config-slot-key-hash-ref
                               seen
                               key))
                       (known? (and entry #t))
                       (next-new-order
                        (if known?
                          new-order
                          (begin
                            (hash-put! seen key (cons key #f))
                            (cons key new-order))))
                       (current
                        (cond
                         ((yuanxu-module-config-slot-key-hash-ref
                           updated
                           key)
                          (if (and (not (eq? merge 'append))
                                   (yuanxu-module-config-slot-key-hash-ref
                                    append-active
                                    key))
                            (flush-append-state! key)
                            (yuanxu-module-config-slot-key-hash-ref
                             updates
                             key)))
                         (known? (cdr entry))
                         (else '())))
                       (append-merge? (eq? merge 'append)))
                  (if append-merge?
                    (let* ((value-changed?
                            (append-slot-value! key current value))
                           (next-changed?
                            (or changed?
                                (not known?)
                                value-changed?)))
                      (when (or (not known?) value-changed?)
                        (hash-put! updated key #t))
                      (apply-contributions (cdr rest)
                                           next-new-order
                                           next-changed?))
                    (let* ((next-value
                            (yuanxu-module-slot-apply-policy
                             merge
                             current
                             value))
                           (value-changed?
                            (not (or (eq? next-value current)
                                     (equal? next-value current))))
                           (next-changed?
                            (or changed?
                                (not known?)
                                value-changed?)))
                      (when (or (not known?) value-changed?)
                        (hash-put! updated key #t)
                        (hash-put! updates key next-value)
                        (record-slot-value-index! key next-value))
                      (apply-contributions (cdr rest)
                                           next-new-order
                                           next-changed?))))
                #f)))))
       ((hash-get seen (caar remaining)) #f)
       (else
       (hash-put! seen (caar remaining) (car remaining))
       (init (cdr remaining)))))))

;; : (-> PooModuleSlotMap [PooModuleFieldContribution] MaybePooModuleSlotMap)
(def (yuanxu-module-config-fast-slot-merge node-identity slots contributions)
  (or (yuanxu-module-config-fast-slot-merge/in-order
       node-identity
       slots
       contributions)
      (yuanxu-module-config-fast-slot-merge/sparse
       node-identity
       slots
       contributions)))

;;; The fast extension result is valid only for childless nodes; child graphs
;;; require the general contribution resolver to preserve nested semantics.
;; : (-> YuanxuGraph [PooModuleFieldContribution] MaybePooGraphResult)
(def (yuanxu-module-config-fast-extension-result base contributions)
  (let ((children (yuanxu-graph-root-children base))
        (node-identity (yuanxu-graph-root-id base))
        (slots (yuanxu-graph-root-payload base)))
    (if (null? children)
      (let (merged-slots
            (yuanxu-module-config-fast-slot-merge
             node-identity
             slots
             contributions))
        (if merged-slots
          (yuanxu-graph-result
           (yuanxu-graph-rooted node-identity merged-slots '())
           (if (equal? merged-slots slots) 0 1)
           #t)
          #f))
      #f)))

;; : (-> YuanxuGraph [PooModuleFieldContribution] PooModuleFieldResolutionResult)
(def (yuanxu-module-field-contributions-resolve base contributions)
  (yuanxu-module-field-resolution-result
   (or (yuanxu-module-config-fast-extension-result base contributions)
       (yuanxu-graph-resolve
        base
        (yuanxu-module-field-contributions->extensions contributions)))
   contributions))
