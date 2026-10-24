;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: module object schema, slot defaults, and object catalog merge.

(import :gerbil/core
        (only-in :clan/poo/object
                 .ref
                 object?
                 object-slots
                 make-object
                 $constant-slot-spec
                 $constant-slot-spec?
                 $constant-slot-spec-value
                 $computed-slot-spec)
        :yuanxu/graph/interface
        :yuanxu/module-system/schema/support/contracts
        :yuanxu/module-system/schema/support/field-resolution)

(import :yuanxu/module-system/schema/support/object-slots)

(export yuanxu-module-object
        yuanxu-module-object?
        yuanxu-module-object-identity
        yuanxu-module-object-inherits
        yuanxu-module-object-fields
        yuanxu-module-object-metadata
        yuanxu-module-object-inheritance-chain-cache
        yuanxu-module-object-validation-cache
        yuanxu-module-object-constant-slot
        yuanxu-module-object-fields-slot
        yuanxu-module-object-constant-slot-ref
        yuanxu-module-object-constant-slot-ref/default
        yuanxu-module-object-field-identity
        yuanxu-module-object-field-index
        yuanxu-module-object-identity-hash-ref
        yuanxu-module-object-field-set
        yuanxu-module-object-fields-merge
        yuanxu-module-object-inherited-fields
        yuanxu-module-object-resolved-fields
        yuanxu-module-object-resolved-field-index
        yuanxu-module-object-field/index
        yuanxu-module-object-field/in-fields
        yuanxu-module-object-field
        yuanxu-module-object-default-slots
        yuanxu-module-object-alist-set
        yuanxu-module-object-slots-merge
        yuanxu-module-object-node/default-slots
        yuanxu-module-object-node
        yuanxu-module-object-contribution
        yuanxu-module-object-contribution/index
        yuanxu-module-object-contributions
        yuanxu-module-objects-node
        yuanxu-module-objects-index
        yuanxu-module-objects-ref/index
        yuanxu-module-objects-ref
        yuanxu-module-objects-contributions-by-target
        yuanxu-module-objects-fast-extension-child-state
        yuanxu-module-objects-fast-extension-result
        yuanxu-module-objects-resolve-contributions/node
        yuanxu-module-objects-resolve-contributions)

;;; Module objects are POO-side schemas. They can inherit fields, but they do
;;; not instantiate modules or evaluate user config.
;; : (-> Symbol [PooModuleObject] [PooModuleFieldContract] PooModuleObjectMetadata PooModuleObject)
(def (yuanxu-module-object identity inherits fields metadata)
  (let ((identity-value identity)
        (inherits-value inherits)
        (fields-value fields)
        (metadata-value metadata))
    (make-object
     ;; Native POO owns precedence and cycle rejection.  `inherits` is retained
     ;; as domain metadata, but it is also the actual prototype parent list.
     supers: inherits-value
     defaults: '((fields . ()))
     slots: (list
             (yuanxu-module-object-constant-slot
              'kind
              yuanxu-module-object-kind)
             (yuanxu-module-object-constant-slot
              'identity
              identity-value)
             (yuanxu-module-object-constant-slot
              'inherits
              inherits-value)
             (yuanxu-module-object-constant-slot
              'direct-fields
              fields-value)
             (yuanxu-module-object-fields-slot fields-value)
             (yuanxu-module-object-constant-slot
              'metadata
              metadata-value)
             (yuanxu-module-object-constant-slot
              'inheritance-chain-cache
              (vector #f '()))
             (yuanxu-module-object-constant-slot
              'validation-cache
              (vector #f #f))))))

;; : (-> PooModuleObjectCandidate Boolean)
(def (yuanxu-module-object? value)
  (and (object? value)
       (let (kind (yuanxu-module-object-constant-slot-ref/default
                   value
                   'kind
                   +yuanxu-module-object-slot-missing+))
         (if (eq? kind +yuanxu-module-object-slot-missing+)
           (yuanxu-module-object-kind? value yuanxu-module-object-kind)
           (equal? kind yuanxu-module-object-kind)))))

;; : (-> PooModuleObject Symbol)
(def (yuanxu-module-object-identity object)
  (yuanxu-module-object-constant-slot-ref object 'identity))
;; : (-> PooModuleObject [PooModuleObject])
(def (yuanxu-module-object-inherits object)
  (yuanxu-module-object-constant-slot-ref object 'inherits))
;; : (-> PooModuleObject [PooModuleFieldContract])
(def (yuanxu-module-object-fields object)
  (yuanxu-module-object-constant-slot-ref object 'direct-fields))
;; : (-> PooModuleObject PooModuleObjectMetadata)
(def (yuanxu-module-object-metadata object)
  (yuanxu-module-object-constant-slot-ref object 'metadata))

;; : (-> PooModuleObject Vector)
(def (yuanxu-module-object-inheritance-chain-cache object)
  (yuanxu-module-object-constant-slot-ref object 'inheritance-chain-cache))

;; : (-> PooModuleObject Vector)
(def (yuanxu-module-object-validation-cache object)
  (yuanxu-module-object-constant-slot-ref object 'validation-cache))

;; : (-> Symbol Value PooModuleObjectSlotSpec)
;;; Descriptor slots are plain POO constant slot specs. Read them from the POO
;;; object's slot table so metadata projections do not instantiate every object.
;; yuanxu-module-object-constant-slot-ref/default
;; : (-> PooModuleObject Symbol Value Value)
;; | doc m%
;;   Read a constant POO slot from a module-system object and return the
;;   provided fallback when the slot is absent or dynamic.
;;   # Examples
;;   ```scheme
;;   (yuanxu-module-object-constant-slot-ref/default object 'enabled? #f)
;;   ;; => #t
;;   ```
;; : (-> PooModuleObject Symbol Value)
;;; Field slots are computed from the superclass chain, letting child objects
;;; override or add fields without duplicating inherited object metadata.
;; : (-> [PooModuleFieldContract] PooModuleObjectSlotSpec)
(def (yuanxu-module-object-fields-slot fields)
  (cons 'fields
        ($computed-slot-spec
         (lambda (_self superfun)
           (yuanxu-module-object-fields-merge
            (superfun)
            fields)))))

;;; Field identity accepts contracts and raw symbols so lookup paths share one
;;; boundary between parsed field contracts and caller-provided keys.
;; : (-> (U PooModuleFieldContract Symbol) Symbol)
;;; Field indexes keep the first declaration authoritative for lookup while
;;; ordered merge code handles replacement and append materialization.
;; : (-> [PooModuleFieldContract] HashTable)
;; : (-> HashTable Symbol Value)
;;; Field set is the small-list replacement path used before hash indexes are
;;; worth materializing, preserving inherited field order.
;; : (-> [PooModuleFieldContract] PooModuleFieldContract [PooModuleFieldContract])
;; yuanxu-module-object-fields-merge
;;   : (-> [PooModuleFieldContract] [PooModuleFieldContract] [PooModuleFieldContract])
;;   | doc m%
;;       `yuanxu-module-object-fields-merge` folds extra contracts through
;;       field identity replacement so inheritance and explicit field override
;;       use the same ordering rule.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-object-fields-merge base-fields extra-fields)
;;       ;; => merged-fields
;;       ```
;;     %
(def (yuanxu-module-object-fields-merge base extra)
  (let ((base-seen (make-hash-table))
        (override-seen (make-hash-table))
        (overrides (make-hash-table))
        (new-seen (make-hash-table))
        (replacement-used (make-hash-table)))
    (for-each
     (lambda (field)
       (hash-put! base-seen
                  (yuanxu-module-object-field-identity field)
                  #t))
     base)
    ;; : (-> Any Any)
    (def (finish-field field)
      (let (identity
            (yuanxu-module-object-field-identity field))
        (if (and (yuanxu-module-object-identity-hash-ref
                  override-seen
                  identity)
                 (not (yuanxu-module-object-identity-hash-ref
                       replacement-used
                       identity)))
          (begin
            (hash-put! replacement-used identity #t)
            (yuanxu-module-object-identity-hash-ref
             overrides
             identity))
          field)))
    ;; : (-> Any Any)
    (def (finish-base/rev fields fields-rev)
      (if (null? fields)
        fields-rev
        (finish-base/rev (cdr fields)
                         (cons (finish-field (car fields)) fields-rev))))
    ;; : (-> Any Any)
    (def (finish-new/rev identities fields-rev)
      (if (null? identities)
        fields-rev
        (finish-new/rev
         (cdr identities)
         (cons (yuanxu-module-object-identity-hash-ref
                overrides
                (car identities))
               fields-rev))))
    ;; : (-> Any Any)
    (def (finish new-identities)
      (reverse
       (finish-new/rev
        (reverse new-identities)
        (finish-base/rev base '()))))
    (let loop ((fields extra) (new-identities '()))
      (if (null? fields)
        (finish new-identities)
        (let* ((field (car fields))
               (identity
                (yuanxu-module-object-field-identity field))
               (next-new-identities
                (if (or (yuanxu-module-object-identity-hash-ref
                         base-seen
                         identity)
                        (yuanxu-module-object-identity-hash-ref
                         new-seen
                         identity))
                  new-identities
                  (begin
                    (hash-put! new-seen identity #t)
                    (cons identity new-identities)))))
          (hash-put! override-seen identity #t)
          (hash-put! overrides identity field)
          (loop (cdr fields) next-new-identities))))))

;;; Inherited field resolution builds a zero-field native POO child.  Parent
;;; precedence, duplicate ancestry, and inconsistent graphs therefore remain
;;; owned by gerbil-poo rather than a second local traversal.
;; : (-> [PooModuleObject] [PooModuleFieldContract])
(def (yuanxu-module-object-inherited-fields inherits)
  (if (null? inherits)
    '()
    (.ref
     (make-object
      supers: inherits
      defaults: '((fields . ()))
      slots: (list (yuanxu-module-object-fields-slot '())))
     'fields)))

;;; Field demand always follows the native lazy slot chain.  Leaf objects hit
;;; the same protocol with the empty `fields` default as their recursion base.
;; : (-> PooModuleObject [PooModuleFieldContract])
(def (yuanxu-module-object-resolved-fields object)
  (.ref object 'fields))

;; : (-> PooModuleObject HashTable)
(def (yuanxu-module-object-resolved-field-index object)
  (yuanxu-module-object-field-index
   (yuanxu-module-object-resolved-fields object)))

;; : (-> HashTable Symbol MaybePooModuleFieldContract)
(def (yuanxu-module-object-field/index field-index identity)
  (yuanxu-module-object-identity-hash-ref field-index identity))

;;; Linear field lookup is retained for one-off access; repeated contribution
;;; mapping should use the indexed lookup path.
;; : (-> [PooModuleFieldContract] Symbol MaybePooModuleFieldContract)
(def (yuanxu-module-object-field/in-fields fields identity)
  (find (lambda (field)
          (equal? (yuanxu-module-object-field-identity field)
                  identity))
        fields))

;; yuanxu-module-object-field
;;   : (-> PooModuleObject Symbol MaybePooModuleFieldContract)
;;   | contract: resolves inherited fields before selecting by identity
;;   | doc m%
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-module-object-field object 'backend)
;;       ;; => field contract or #f
;;       ```
;;     %
(def (yuanxu-module-object-field object identity)
  (yuanxu-module-object-field/in-fields
   (yuanxu-module-object-resolved-fields object)
   identity))

;;; Default slot materialization is a pure projection from field contracts;
;;; override rows merge only after every identity has its contract-owned value.
;; : (-> PooModuleObject PooModuleSlotMap)
(def (yuanxu-module-object-default-slots object)
  (map (lambda (field)
         (cons (yuanxu-module-field-contract-identity field)
               (yuanxu-module-field-contract-default field)))
       (yuanxu-module-object-resolved-fields object)))

;;; Slot alist replacement preserves the first key position and updates only
;;; the matching row, matching extension slot merge order.
;; : (-> PooModuleSlotMap Symbol PooModuleSlotValue PooModuleSlotMap)
(def (yuanxu-module-object-alist-set entries key value)
  (cond ((null? entries) (list (cons key value)))
        ((equal? (caar entries) key) (cons (cons key value) (cdr entries)))
        (else (cons (car entries)
                    (yuanxu-module-object-alist-set
                     (cdr entries)
                     key
                     value)))))

;; yuanxu-module-object-slots-merge
;;   : (-> PooModuleSlotMap PooModuleSlotMap PooModuleSlotMap)
;;   | doc m%
;;       `yuanxu-module-object-slots-merge` folds object rows through the
;;       alist setter, preserving first declaration order while allowing later
;;       rows to override by key.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-object-slots-merge base-slots extra-slots)
;;       ;; => merged-slots
;;       ```
;;     %
(def (yuanxu-module-object-slots-merge base extra)
  (let ((base-seen (make-hash-table))
        (override-seen (make-hash-table))
        (overrides (make-hash-table))
        (new-seen (make-hash-table))
        (replacement-used (make-hash-table)))
    (for-each
     (lambda (entry)
       (hash-put! base-seen (car entry) #t))
     base)
    ;; : (-> Any Any)
    (def (finish-entry entry)
      (let (key (car entry))
        (if (and (yuanxu-module-config-slot-key-hash-ref
                  override-seen
                  key)
                 (not (yuanxu-module-config-slot-key-hash-ref
                       replacement-used
                       key)))
          (begin
            (hash-put! replacement-used key #t)
            (cons key
                  (yuanxu-module-config-slot-key-hash-ref
                   overrides
                   key)))
          entry)))
    ;; : (-> Any Any)
    (def (finish-base/rev entries rows-rev)
      (if (null? entries)
        rows-rev
        (finish-base/rev (cdr entries)
                         (cons (finish-entry (car entries)) rows-rev))))
    ;; : (-> Any Any)
    (def (finish-new/rev keys rows-rev)
      (if (null? keys)
        rows-rev
        (finish-new/rev
         (cdr keys)
         (cons (cons (car keys)
                     (yuanxu-module-config-slot-key-hash-ref
                      overrides
                      (car keys)))
               rows-rev))))
    ;; : (-> Any Any)
    (def (finish new-keys)
      (reverse
       (finish-new/rev
        (reverse new-keys)
        (finish-base/rev base '()))))
    (let loop ((entries extra) (new-keys '()))
      (if (null? entries)
        (finish new-keys)
        (let* ((entry (car entries))
               (key (car entry))
               (next-new-keys
                (if (or (yuanxu-module-config-slot-key-hash-ref
                         base-seen
                         key)
                        (yuanxu-module-config-slot-key-hash-ref
                         new-seen
                         key))
                  new-keys
                  (begin
                    (hash-put! new-seen key #t)
                    (cons key new-keys)))))
          (hash-put! override-seen key #t)
          (hash-put! overrides key (cdr entry))
          (loop (cdr entries) next-new-keys))))))

;;; Object nodes are extension nodes seeded with field defaults; downstream
;;; contributions only need to provide changed slots.
;; : (-> PooModuleObject PooModuleSlotMap [YuanxuGraph] YuanxuGraph)
(def (yuanxu-module-object-node/default-slots object default-slots slots children)
  (yuanxu-graph-rooted
   (yuanxu-module-object-identity object)
   (yuanxu-module-object-slots-merge
    default-slots
    slots)
   children))

;; : (-> PooModuleObject PooModuleSlotMap [YuanxuGraph] YuanxuGraph)
(def (yuanxu-module-object-node object slots children)
  (yuanxu-module-object-node/default-slots
   object
   (yuanxu-module-object-default-slots object)
   slots
   children))

;;; Object contribution converts one user slot row into a typed field
;;; contribution and fails loudly when the object schema has no such field.
;; : (-> PooModuleObject Pair PooModuleFieldContribution)
(def (yuanxu-module-object-contribution object entry)
  (let (field (yuanxu-module-object-field object (car entry)))
    (if field
      (yuanxu-module-field-contribution
       (yuanxu-module-object-identity object)
       field
       (cdr entry))
      (error "unknown Yuanxu module object field"
             (yuanxu-module-object-identity object)
             (car entry)))))

;;; Indexed contribution conversion keeps large object updates from rescanning
;;; resolved fields for every user-provided row.
;; : (-> PooModuleObject HashTable Pair PooModuleFieldContribution)
(def (yuanxu-module-object-contribution/index object field-index entry)
  (let (field (hash-get field-index (car entry)))
    (if field
      (yuanxu-module-field-contribution
       (yuanxu-module-object-identity object)
       field
       (cdr entry))
      (error "unknown Yuanxu module object field"
             (yuanxu-module-object-identity object)
             (car entry)))))

;;; Object contribution mapping preserves one indexed field-contract lookup per
;;; user row, keeping unknown fields as failures instead of silent slots.
;; : (-> PooModuleObject PooModuleObjectContributionEntries [PooModuleFieldContribution])
(def (yuanxu-module-object-contributions object entries)
  (let (field-index
        (yuanxu-module-object-resolved-field-index object))
    (map (lambda (entry)
           (yuanxu-module-object-contribution/index
            object
            field-index
            entry))
         entries)))

;;; The object namespace is a regular extension graph root; object schemas
;;; project independently into child nodes before runtime contributions merge.
;; : (-> [PooModuleObject] [YuanxuGraph])
(def (yuanxu-module-object-nodes objects)
  (map (lambda (object)
         (yuanxu-module-object-node object '() '()))
       objects))

;; : (-> [PooModuleObject] YuanxuGraph)
(def (yuanxu-module-objects-node objects)
  (yuanxu-graph-rooted
   yuanxu-module-objects-root-identity
   '((namespace . objects))
   (yuanxu-module-object-nodes objects)))

;;; Object indexes materialize the catalog identity boundary once so inherit and
;;; merge callers can resolve child nodes without repeated child scans.
;; : (-> YuanxuGraph HashTable)
(def (yuanxu-module-objects-index objects-node)
  (let (index (make-hash-table))
    (for-each
     (lambda (child)
       (hash-put! index
                  (yuanxu-graph-root-id child)
                  child))
     (yuanxu-graph-root-children objects-node))
    index))

;; : (-> HashTable Symbol MaybeYuanxuGraph)
(def (yuanxu-module-objects-ref/index objects-index identity)
  (yuanxu-module-object-identity-hash-ref objects-index identity))

;; : (-> YuanxuGraph Symbol MaybeYuanxuGraph)
(def (yuanxu-module-objects-ref objects-node identity)
  (yuanxu-graph-root-ref
   (yuanxu-graph-root-children objects-node)
   identity))

;; yuanxu-module-objects-contributions-by-target
;;   : (-> [PooModuleFieldContribution] HashTable)
;;   | doc m%
;;       `yuanxu-module-objects-contributions-by-target` groups field
;;       contributions by target identity so extension children can be updated
;;       without repeatedly scanning the full contribution list.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-objects-contributions-by-target contributions)
;;       ;; => target-contribution-table
;;       ```
;;     %
(def (yuanxu-module-objects-contributions-by-target contributions)
  (let (groups (make-hash-table))
    (let loop ((remaining contributions))
      (if (null? remaining)
        groups
        (let* ((contribution (car remaining))
               (target
                (yuanxu-module-field-contribution-target contribution))
               (group (hash-get groups target)))
          (hash-put! groups
                     target
                     (if group
                       (cons contribution group)
                       (list contribution)))
          (loop (cdr remaining)))))))

;;; Fast child state updates only children that have grouped contributions while
;;; preserving untouched child nodes and tracking whether any merge changed.
;; : (-> HashTable MaybeFastExtensionChildState YuanxuGraph MaybeFastExtensionChildState)
(def (yuanxu-module-objects-fast-extension-child-state groups state child)
  (and state
       (let* ((next-children (car state))
              (changed? (cdr state))
              (target (yuanxu-graph-root-id child))
              (target-contributions (hash-get groups target)))
         (if target-contributions
           (let (child-result
                 (yuanxu-module-config-fast-extension-result
                  child
                  (reverse target-contributions)))
             (and child-result
                  (let ((next-child
                         (yuanxu-graph-result-root child-result))
                        (child-changed?
                         (> (yuanxu-graph-result-changed-passes
                             child-result)
                            0)))
                    (cons (cons next-child next-children)
                          (or changed? child-changed?)))))
          (cons (cons child next-children) changed?)))))

;; : (-> HashTable [YuanxuGraph] MaybeFastExtensionChildState MaybeFastExtensionChildState)
(def (yuanxu-module-objects-fast-extension-child-state/fold
      groups
      children
      state)
  (if (null? children)
    state
    (yuanxu-module-objects-fast-extension-child-state/fold
     groups
     (cdr children)
     (yuanxu-module-objects-fast-extension-child-state
      groups
      state
      (car children)))))

;;; Fast extension result is valid only for contributions to direct children.
;;; A root-targeted operation must run through the extension graph so it can
;;; update root slots (or extend/remove children) before child contributions.
;; : (-> YuanxuGraph [PooModuleFieldContribution] MaybePooGraphResult)
(def (yuanxu-module-objects-fast-extension-result objects-node contributions)
  (and (equal? (yuanxu-graph-root-id objects-node)
               yuanxu-module-objects-root-identity)
       (let* ((groups
               (yuanxu-module-objects-contributions-by-target contributions))
              (slots
               (yuanxu-graph-root-payload objects-node))
              (state
               (yuanxu-module-objects-fast-extension-child-state/fold
                groups
                (yuanxu-graph-root-children objects-node)
                (cons '() #f))))
         (and (not (hash-get groups yuanxu-module-objects-root-identity))
              state
              (yuanxu-graph-result
               (yuanxu-graph-rooted
                yuanxu-module-objects-root-identity
                slots
                (reverse (car state)))
               (if (cdr state) 1 0)
               #t)))))

;;; Object contribution resolution prefers the objects-root fast path and
;;; delegates to the generic extension graph outside that proven boundary.
;; : (-> YuanxuGraph [PooModuleFieldContribution] PooModuleFieldResolutionResult)
(def (yuanxu-module-objects-resolve-contributions/node
      objects-node contributions)
  (let (fast-result
        (yuanxu-module-objects-fast-extension-result objects-node
                                                       contributions))
    (if fast-result
      (yuanxu-module-field-resolution-result fast-result contributions)
      (yuanxu-module-field-contributions-resolve
       objects-node contributions))))

;; : (-> [PooModuleObject] [PooModuleFieldContribution] PooModuleFieldResolutionResult)
(def (yuanxu-module-objects-resolve-contributions objects contributions)
  (yuanxu-module-objects-resolve-contributions/node
   (yuanxu-module-objects-node objects)
   contributions))
