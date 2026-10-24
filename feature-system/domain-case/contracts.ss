;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: owns internal CaseComponent and DomainCase closure contracts.
;;; Invariant: this module exposes no parallel public DSL.

(export #t)

(import (only-in :clan/poo/object .ref object?)
        (only-in :std/crypto/digest sha256)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/list/list every)
        :yuanxu/object-family/role-syntax
        :yuanxu/composition/roles
        (only-in :yuanxu/utilities/functional
                 yuanxu-fold-left
                 yuanxu-fold-right
                 yuanxu-map
                 yuanxu-filter-map
                 yuanxu-append-map
                 yuanxu-all?
                 yuanxu-stable-duplicates
                 yuanxu-member?
                 yuanxu-list-of?))

(def +yuanxu-case-slot-contract-kind+ 'yuanxu.case-slot-contract.v1)
(def +yuanxu-case-type-contract-kind+ 'yuanxu.case-type-contract.v1)
(def +yuanxu-case-method-contract-kind+ 'yuanxu.case-method-contract.v1)
(def +yuanxu-case-projection-kind+ 'yuanxu.case-projection.v1)
(def +yuanxu-case-component-kind+ 'yuanxu.case-component.v1)
(def +yuanxu-domain-case-kind+ 'yuanxu.domain-case.v1)
(def +yuanxu-domain-case-cache-kind+ 'yuanxu.domain-case-cache.v1)
(def +yuanxu-domain-case-closure-receipt-kind+
  'yuanxu.domain-case-closure-receipt.v1)
(def +yuanxu-domain-case-instance-receipt-kind+
  'yuanxu.domain-case-instance-receipt.v1)
(def +yuanxu-domain-case-method-receipt-kind+
  'yuanxu.domain-case-method-receipt.v1)
(def +yuanxu-domain-case-projection-receipt-kind+
  'yuanxu.domain-case-projection-receipt.v1)
(def +yuanxu-domain-case-key-domain+ 'yuanxu.domain-case-key.v1)

(def (domain-case-id? value)
  (or (symbol? value)
      (and (string? value) (> (string-length value) 0))))

(def (domain-case-object-kind? value expected)
  (with-catch (lambda (_failure) #f)
              (lambda () (eq? (.ref value 'kind) expected))))

(def (domain-case-safe-call predicate value)
  (with-catch (lambda (_failure) #f)
              (lambda () (and (predicate value) #t))))

(def (domain-case-safe-binary-call predicate left right)
  (with-catch (lambda (_failure) #f)
              (lambda () (and (predicate left right) #t))))

(def (domain-case-id->string value)
  (cond
   ((symbol? value) (symbol->string value))
   ((string? value) value)
   (else (call-with-output-string (lambda (port) (write value port))))))

(def (domain-case-sort values id-of)
  (list-sort (lambda (left right)
               (string<? (domain-case-id->string (id-of left))
                         (domain-case-id->string (id-of right))))
             (append values '())))

(def (domain-case-sort-ids values)
  (list-sort (lambda (left right)
               (string<? (domain-case-id->string left)
                         (domain-case-id->string right)))
             (append values '())))

(def (domain-case-unique values)
  (delete-duplicates/hash values from-end?: #t))

(def (domain-case-duplicates values)
  (yuanxu-stable-duplicates values))

(def (domain-case-every-eq? left right)
  (and (= (length left) (length right))
       (if (every eq? left right) #t #f)))

(def (yuanxu-case-slot-contract slot-id-value owner-id-value type-id-value
                                  default-id-value merge-algebra-value
                                  (override-owner-ids-value '())
                                  (compatibility-witness-id-value #f)
                                  (validator-value #f))
  (poo-core-role-object
   (slots ((kind +yuanxu-case-slot-contract-kind+)
           (slot-id slot-id-value)
           (owner-id owner-id-value)
           (type-id type-id-value)
           (default-id default-id-value)
           (merge-algebra merge-algebra-value)
           (override-owner-ids override-owner-ids-value)
           (compatibility-witness-id compatibility-witness-id-value)
           (validator validator-value)))
   (supers)))

(def (yuanxu-case-slot-contract? value)
  (domain-case-object-kind? value +yuanxu-case-slot-contract-kind+))

(def (yuanxu-case-type-contract type-id-value parent-type-ids-value
                                  predicate-value)
  (poo-core-role-object
   (slots ((kind +yuanxu-case-type-contract-kind+)
           (type-id type-id-value)
           (parent-type-ids parent-type-ids-value)
           (predicate predicate-value)))
   (supers)))

(def (yuanxu-case-type-contract? value)
  (domain-case-object-kind? value +yuanxu-case-type-contract-kind+))

(def (yuanxu-case-method-contract contract-id-value owner-id-value
                                    subject-id-value contract-kind-value
                                    domain-id-value precondition-id-value
                                    postcondition-id-value validator-value
                                    (refines-contract-ids-value '())
                                    (compatibility-witness-id-value #f)
                                    (compatibility-witness-value #f))
  (poo-core-role-object
   (slots ((kind +yuanxu-case-method-contract-kind+)
           (contract-id contract-id-value)
           (owner-id owner-id-value)
           (subject-id subject-id-value)
           (contract-kind contract-kind-value)
           (domain-id domain-id-value)
           (precondition-id precondition-id-value)
           (postcondition-id postcondition-id-value)
           (validator validator-value)
           (refines-contract-ids refines-contract-ids-value)
           (compatibility-witness-id compatibility-witness-id-value)
           (compatibility-witness compatibility-witness-value)))
   (supers)))

(def (yuanxu-case-method-contract? value)
  (domain-case-object-kind? value +yuanxu-case-method-contract-kind+))

(def (yuanxu-case-projection projection-id-value owner-id-value
                               schema-id-value projector-value)
  (poo-core-role-object
   (slots ((kind +yuanxu-case-projection-kind+)
           (projection-id projection-id-value)
           (owner-id owner-id-value)
           (schema-id schema-id-value)
           (projector projector-value)))
   (supers)))

(def (yuanxu-case-projection? value)
  (domain-case-object-kind? value +yuanxu-case-projection-kind+))

(def (yuanxu-case-component component-id-value component-version-value
                              role-prototype-value type-contract-value
                              slot-contracts-value method-contracts-value
                              projections-value
                              (parent-component-ids-value '())
                              (policy-algebra-value #f)
                              (strategy-algebra-value #f))
  (poo-core-role-object
   (slots ((kind +yuanxu-case-component-kind+)
           (component-id component-id-value)
           (component-version component-version-value)
           (role-prototype role-prototype-value)
           (type-contract type-contract-value)
           (slot-contracts slot-contracts-value)
           (method-contracts method-contracts-value)
           (projections projections-value)
           (parent-component-ids parent-component-ids-value)
           (policy-algebra policy-algebra-value)
           (strategy-algebra strategy-algebra-value)))
   (supers)))

(def (yuanxu-case-component? value)
  (domain-case-object-kind? value +yuanxu-case-component-kind+))

(def (case-slot-contract-valid? value)
  (and (yuanxu-case-slot-contract? value)
       (domain-case-id? (.ref value 'slot-id))
       (domain-case-id? (.ref value 'owner-id))
       (domain-case-id? (.ref value 'type-id))
       (domain-case-id? (.ref value 'default-id))
       (domain-case-id? (.ref value 'merge-algebra))
       (yuanxu-list-of? domain-case-id?
                          (.ref value 'override-owner-ids))
       (or (not (.ref value 'compatibility-witness-id))
           (domain-case-id? (.ref value 'compatibility-witness-id)))
       (procedure? (.ref value 'validator))))

(def (case-type-contract-valid? value)
  (and (yuanxu-case-type-contract? value)
       (domain-case-id? (.ref value 'type-id))
       (yuanxu-list-of? domain-case-id? (.ref value 'parent-type-ids))
       (procedure? (.ref value 'predicate))))

(def (case-method-contract-valid? value)
  (and (yuanxu-case-method-contract? value)
       (domain-case-id? (.ref value 'contract-id))
       (domain-case-id? (.ref value 'owner-id))
       (domain-case-id? (.ref value 'subject-id))
       (memq (.ref value 'contract-kind) '(state method))
       (domain-case-id? (.ref value 'domain-id))
       (domain-case-id? (.ref value 'precondition-id))
       (domain-case-id? (.ref value 'postcondition-id))
       (procedure? (.ref value 'validator))
       (yuanxu-list-of? domain-case-id?
                          (.ref value 'refines-contract-ids))
       (or (and (null? (.ref value 'refines-contract-ids))
                (not (.ref value 'compatibility-witness-id))
                (not (.ref value 'compatibility-witness)))
           (and (pair? (.ref value 'refines-contract-ids))
                (domain-case-id?
                 (.ref value 'compatibility-witness-id))
                (procedure? (.ref value 'compatibility-witness))))))

(def (case-projection-valid? value)
  (and (yuanxu-case-projection? value)
       (domain-case-id? (.ref value 'projection-id))
       (domain-case-id? (.ref value 'owner-id))
       (domain-case-id? (.ref value 'schema-id))
       (procedure? (.ref value 'projector))))

(def (yuanxu-case-component-valid? value)
  (and (yuanxu-case-component? value)
       (domain-case-id? (.ref value 'component-id))
       (exact-integer? (.ref value 'component-version))
       (> (.ref value 'component-version) 0)
       (.ref value 'role-prototype)
       (case-type-contract-valid? (.ref value 'type-contract))
       (yuanxu-list-of? case-slot-contract-valid?
                          (.ref value 'slot-contracts))
       (yuanxu-list-of? case-method-contract-valid?
                          (.ref value 'method-contracts))
       (yuanxu-list-of? case-projection-valid?
                          (.ref value 'projections))
       (yuanxu-list-of? domain-case-id?
                          (.ref value 'parent-component-ids))
       (or (not (.ref value 'policy-algebra))
           (domain-case-id? (.ref value 'policy-algebra)))
       (or (not (.ref value 'strategy-algebra))
           (domain-case-id? (.ref value 'strategy-algebra)))))

(def (case-slot-contract-normalize value)
  (list 'slot
        (.ref value 'slot-id)
        (.ref value 'owner-id)
        (.ref value 'type-id)
        (.ref value 'default-id)
        (.ref value 'merge-algebra)
        (cons 'overrides
              (list-sort (lambda (left right)
                           (string<? (domain-case-id->string left)
                                     (domain-case-id->string right)))
                         (append (.ref value 'override-owner-ids) '())))
        (list 'witness (.ref value 'compatibility-witness-id))))

(def (case-type-contract-normalize value)
  (list 'type
        (.ref value 'type-id)
        (cons 'parents (.ref value 'parent-type-ids))))

(def (case-method-contract-normalize value)
  (list 'contract
        (.ref value 'contract-id)
        (.ref value 'owner-id)
        (.ref value 'subject-id)
        (.ref value 'contract-kind)
        (.ref value 'domain-id)
        (.ref value 'precondition-id)
        (.ref value 'postcondition-id)
        (cons 'refines
              (list-sort (lambda (left right)
                           (string<? (domain-case-id->string left)
                                     (domain-case-id->string right)))
                         (append (.ref value 'refines-contract-ids) '())))
        (list 'witness (.ref value 'compatibility-witness-id))))

(def (case-projection-normalize value)
  (list 'projection
        (.ref value 'projection-id)
        (.ref value 'owner-id)
        (.ref value 'schema-id)))

(def (case-component-normalize value)
  (list 'component
        (.ref value 'component-id)
        (.ref value 'component-version)
        (cons 'parents (.ref value 'parent-component-ids))
        (case-type-contract-normalize (.ref value 'type-contract))
        (cons 'slots
              (yuanxu-map
               case-slot-contract-normalize
               (domain-case-sort (.ref value 'slot-contracts)
                                 (lambda (slot) (.ref slot 'slot-id)))))
        (cons 'contracts
              (yuanxu-map
               case-method-contract-normalize
               (domain-case-sort
                (.ref value 'method-contracts)
                (lambda (contract) (.ref contract 'contract-id)))))
        (cons 'projections
              (yuanxu-map
               case-projection-normalize
               (domain-case-sort
                (.ref value 'projections)
                (lambda (projection) (.ref projection 'projection-id)))))
        (list 'policy-algebra (.ref value 'policy-algebra))
        (list 'strategy-algebra (.ref value 'strategy-algebra))))

(def (yuanxu-domain-case-canonical-descriptor schema-id-value
                                                schema-version-value
                                                components
                                                local-overrides
                                                selected-projection-ids)
  (list +yuanxu-domain-case-key-domain+
        (list 'schema-id schema-id-value)
        (list 'schema-version schema-version-value)
        (cons 'components (yuanxu-map case-component-normalize components))
        (cons 'local-overrides
              (yuanxu-map
               case-slot-contract-normalize
               (domain-case-sort local-overrides
                                 (lambda (slot) (.ref slot 'slot-id)))))
        (cons 'selected-projections
              (domain-case-sort-ids selected-projection-ids))))

(def (yuanxu-domain-case-canonical-key descriptor)
  (hex-encode
   (sha256
    (string->utf8
     (call-with-output-string (lambda (port) (write descriptor port)))))))

(def (domain-case-diagnostic code path observed)
  (poo-core-role-object
   (slots ((kind 'yuanxu.domain-case-diagnostic.v1)
           (code code)
           (path path)
           (observed observed)))
   (supers)))

(def (domain-case-slot-equivalent? left right)
  (equal? (case-slot-contract-normalize left)
          (case-slot-contract-normalize right)))

(def (domain-case-explicit-override? candidate inherited)
  (and (yuanxu-member? (.ref inherited 'owner-id)
                         (.ref candidate 'override-owner-ids))
       (.ref candidate 'compatibility-witness-id)))

;; Resolution entries let an override retire the former winner in O(1) while
;; retaining the exact source-order projection of the reference algorithm.
(def (domain-case-resolution-entry value)
  (vector value #t))

(def (domain-case-resolution-entry-value entry)
  (vector-ref entry 0))

(def (domain-case-resolution-entry-active? entry)
  (vector-ref entry 1))

(def (domain-case-resolution-retire! entry)
  (vector-set! entry 1 #f))

(def (domain-case-resolution-values entries-rev)
  (yuanxu-filter-map
   (lambda (entry)
     (and (domain-case-resolution-entry-active? entry)
          (domain-case-resolution-entry-value entry)))
   (reverse entries-rev)))

(def (domain-case-resolve-slots slots)
  (let ((winner-index (make-hash-table)))
    (let loop ((rest slots) (entries-rev '()) (diagnostics '()))
    (if (null? rest)
        (values (domain-case-resolution-values entries-rev)
                (reverse diagnostics))
        (let* ((candidate (car rest))
               (slot-id (.ref candidate 'slot-id))
               (existing-entry (hash-get winner-index slot-id))
               (existing
                (and existing-entry
                     (domain-case-resolution-entry-value existing-entry))))
          (cond
           ((not existing)
            (let (entry (domain-case-resolution-entry candidate))
              (hash-put! winner-index slot-id entry)
              (loop (cdr rest) (cons entry entries-rev) diagnostics)))
           ((domain-case-slot-equivalent? existing candidate)
            (loop (cdr rest) entries-rev diagnostics))
           ((and (domain-case-explicit-override? candidate existing)
                 (domain-case-explicit-override? existing candidate))
            (loop (cdr rest) entries-rev
                  (cons (domain-case-diagnostic
                         'ambiguous-slot-override
                         (list 'slots slot-id)
                         (list (.ref existing 'owner-id)
                               (.ref candidate 'owner-id)))
                        diagnostics)))
           ((domain-case-explicit-override? candidate existing)
            (domain-case-resolution-retire! existing-entry)
            (let (entry (domain-case-resolution-entry candidate))
              (hash-put! winner-index slot-id entry)
              (loop (cdr rest) (cons entry entries-rev) diagnostics)))
           ((domain-case-explicit-override? existing candidate)
            (loop (cdr rest) entries-rev diagnostics))
           (else
            (loop (cdr rest) entries-rev
                  (cons (domain-case-diagnostic
                         'slot-contract-conflict
                         (list 'slots slot-id)
                         (list (case-slot-contract-normalize existing)
                               (case-slot-contract-normalize candidate)))
                        diagnostics)))))))))

(def (domain-case-contract-equivalent? left right)
  (equal? (case-method-contract-normalize left)
          (case-method-contract-normalize right)))

(def (domain-case-contract-refines? candidate inherited)
  (and (yuanxu-member? (.ref inherited 'contract-id)
                         (.ref candidate 'refines-contract-ids))
       (equal? (.ref candidate 'domain-id) (.ref inherited 'domain-id))
       (domain-case-safe-binary-call
        (.ref candidate 'compatibility-witness) candidate inherited)))

(def (domain-case-resolve-method-contracts contracts)
  (let ((winner-index (make-hash-table)))
    (let loop ((rest contracts) (entries-rev '()) (diagnostics '()))
    (if (null? rest)
        (values (domain-case-resolution-values entries-rev)
                (reverse diagnostics))
        (let* ((candidate (car rest))
               (kind (.ref candidate 'contract-kind))
               (subject-id (.ref candidate 'subject-id))
               (existing-entry
                (and (eq? kind 'method)
                     (hash-get winner-index subject-id)))
               (existing
                (and existing-entry
                     (domain-case-resolution-entry-value existing-entry))))
          (cond
           ((or (eq? kind 'state) (not existing))
            (let (entry (domain-case-resolution-entry candidate))
              (when (eq? kind 'method)
                (hash-put! winner-index subject-id entry))
              (loop (cdr rest) (cons entry entries-rev) diagnostics)))
           ((domain-case-contract-equivalent? existing candidate)
            (loop (cdr rest) entries-rev diagnostics))
           ((and (domain-case-contract-refines? candidate existing)
                 (domain-case-contract-refines? existing candidate))
            (loop (cdr rest) entries-rev
                  (cons (domain-case-diagnostic
                         'ambiguous-contract-refinement
                         (list 'contracts subject-id)
                         (list (.ref existing 'contract-id)
                               (.ref candidate 'contract-id)))
                        diagnostics)))
           ((domain-case-contract-refines? candidate existing)
            (domain-case-resolution-retire! existing-entry)
            (let (entry (domain-case-resolution-entry candidate))
              (hash-put! winner-index subject-id entry)
              (loop (cdr rest) (cons entry entries-rev) diagnostics)))
           ((domain-case-contract-refines? existing candidate)
            (loop (cdr rest) entries-rev diagnostics))
           (else
            (loop (cdr rest) entries-rev
                  (cons (domain-case-diagnostic
                         'contract-refinement-conflict
                         (list 'contracts subject-id)
                         (list (.ref existing 'contract-id)
                               (.ref candidate 'contract-id)))
                        diagnostics)))))))))

(def (domain-case-projection-conflicts projections)
  (let ((seen (make-hash-table))
        (diagnostics-rev '()))
    (for-each
     (lambda (candidate)
       (let* ((id (.ref candidate 'projection-id))
              (existing (hash-get seen id)))
         (if existing
           (set! diagnostics-rev
                 (cons
                  (domain-case-diagnostic
                   'projection-name-conflict
                   (list 'projections id)
                   (list (.ref existing 'owner-id)
                         (.ref candidate 'owner-id)))
                  diagnostics-rev))
           (hash-put! seen id candidate))))
     projections)
    (reverse diagnostics-rev)))

(def (domain-case-single-algebra components slot code)
  (let (algebras
        (domain-case-unique
         (yuanxu-filter-map
          (lambda (component) (.ref component slot))
          components)))
    (if (> (length algebras) 1)
        (values #f (list (domain-case-diagnostic code (list slot) algebras)))
        (values (and (pair? algebras) (car algebras)) '()))))

(def (domain-case-parent-diagnostics components)
  (let ((seen (make-hash-table))
        (diagnostics-rev '()))
    (for-each
     (lambda (component)
       (let (id (.ref component 'component-id))
         (for-each
          (lambda (parent-id)
            (unless (hash-key? seen parent-id)
              (set! diagnostics-rev
                    (cons
                     (domain-case-diagnostic
                      'missing-or-forward-parent-component
                      (list 'components id 'parents)
                      parent-id)
                     diagnostics-rev))))
          (.ref component 'parent-component-ids))
         (hash-put! seen id #t)))
     components)
    (reverse diagnostics-rev)))

(def (domain-case-type-diagnostics components)
  (let ((seen (make-hash-table))
        (diagnostics-rev '()))
    (for-each
     (lambda (component)
       (let* ((type-contract (.ref component 'type-contract))
              (type-id (.ref type-contract 'type-id))
              (existing (hash-get seen type-id)))
         (when (and existing (not (eq? existing type-contract)))
           (set! diagnostics-rev
                 (cons
                  (domain-case-diagnostic
                   'type-identity-conflict
                   (list 'types type-id)
                   (list (.ref existing 'parent-type-ids)
                         (.ref type-contract 'parent-type-ids)))
                  diagnostics-rev)))
         (for-each
          (lambda (parent-id)
            (unless (hash-key? seen parent-id)
              (set! diagnostics-rev
                    (cons
                     (domain-case-diagnostic
                      'missing-or-forward-parent-type
                      (list 'types type-id 'parents)
                      parent-id)
                     diagnostics-rev))))
          (.ref type-contract 'parent-type-ids))
         (unless existing
           (hash-put! seen type-id type-contract))))
     components)
    (reverse diagnostics-rev)))

(def (domain-case-select-projections projections selected-ids)
  (let ((projection-index (make-hash-table)))
    (for-each
     (lambda (projection)
       (let* ((id (.ref projection 'projection-id))
              (entry (hash-get projection-index id)))
         (if entry
           (vector-set! entry 0 (+ 1 (vector-ref entry 0)))
           (hash-put! projection-index id (vector 1 projection)))))
     projections)
    (let (catalog+diagnostics
        (yuanxu-fold-right
         (lambda (id state)
           (let* ((catalog (car state))
                  (diagnostics (cdr state))
                  (entry (hash-get projection-index id)))
             (cond
              ((not entry)
               (cons catalog
                     (cons (domain-case-diagnostic
                            'unknown-projection
                            (list 'selected-projections id) #f)
                           diagnostics)))
              ((> (vector-ref entry 0) 1) state)
              (else
               (cons (cons (vector-ref entry 1) catalog) diagnostics)))))
         (cons '() '())
         selected-ids))
      (values (car catalog+diagnostics) (cdr catalog+diagnostics)))))
