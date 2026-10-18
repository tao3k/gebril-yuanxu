;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: POO Flow domain specialization of standard gerbil-poo types.
;;; Invariant: gerbil-poo owns primitive Type validation and prototype dispatch;
;;; this module owns only evidence-bearing POO Flow classification/contracts.

(import (only-in :clan/poo/object
                 .cc
                 .all-slots
                 .o
                 .ref
                 .slot?
                 compute-precedence-list!
                 object?)
        (only-in :clan/poo/mop
                 .defgeneric
                 define-type
                 Type
                 Type.
                 element?
                 validate
                 raise-type-error)
        (only-in :std/list/list every)
)

(export PooFlowType.
        PooFlowContract.
        PooFlowNativeObjectContract.
        PooFlowClassificationEvidence
        PooFlowValidationEvidence
        poo-flow-predicate-type
        poo-flow-predicate-contract
        poo-flow-type-classify
        poo-flow-contract-obligations
        poo-flow-context-contract-obligations
        poo-flow-contract-admit
        poo-flow-classification-evidence
        poo-flow-classification-evidence?
        poo-flow-classification-evidence-accepted?
        poo-flow-classification-evidence->alist
        poo-flow-validation-evidence
        poo-flow-validation-evidence?
        poo-flow-validation-evidence-accepted?
        poo-flow-validation-evidence->alist)

;; Open POO protocols dispatch through descriptor slots.  They are intentionally
;; sparse: fixed accessors and final receipt encoders remain ordinary functions.
(.defgeneric (poo-flow-type-classify type candidate context)
  slot: .classify)

;;; Protocol boundary: obligation dispatch stays on the contract descriptor.
(.defgeneric (poo-flow-contract-obligations contract candidate context)
  slot: .obligations)

;; Optional platform policy; domain Contract identity and own methods stay intact.
(.defgeneric (poo-flow-context-contract-obligations context contract candidate)
  slot: .contract-obligations)

(def (context-contract-obligations context contract candidate)
  (if (and (object? context) (.slot? context '.contract-obligations))
    (let (issues (poo-flow-context-contract-obligations context contract candidate))
      (unless (list? issues) (error "Context contract obligations must return diagnostics"))
      issues)
    '()))

;;; Protocol boundary: admission returns evidence rather than a bare boolean.
(.defgeneric (poo-flow-contract-admit contract candidate context)
  slot: .admit)

;; : (-> Object Symbol [Symbol] Boolean)
(def (poo-flow-evidence-object? value expected-kind required-slots)
  (and (object? value)
       (every (cut .slot? value <>) required-slots)
       (eq? (.ref value 'kind) expected-kind)
       (boolean? (.ref value 'accepted?))
       (list? (.ref value 'diagnostics))))

;; : (-> Object Boolean)
(def (poo-flow-type-identity? value)
  (or (symbol? value)
      (and (pair? value)
           (list? value)
           (every poo-flow-type-identity? value))))

;; : (-> Object Boolean)
(def (poo-flow-classification-evidence-element? value)
  (and (poo-flow-evidence-object?
        value 'poo-flow.type.classification-evidence
        '(kind type-identity candidate accepted? diagnostics context))
       (poo-flow-type-identity? (.ref value 'type-identity))))

;;; Evidence type: accepts only classification receipts with the required typed slots.
(define-type (PooFlowClassificationEvidence @ Type.)
  .element?: poo-flow-classification-evidence-element?)

;; : (-> Object Boolean)
(def (poo-flow-validation-evidence-element? value)
  (and (poo-flow-evidence-object?
        value 'poo-flow.contract.validation-evidence
        '(kind contract-identity admission-contract candidate classification obligation-evidence
               accepted? diagnostics context))
       (symbol? (.ref value 'contract-identity))
       (object? (.ref value 'admission-contract))
       (.slot? (.ref value 'admission-contract) 'identity)
       (eq? (.ref value 'contract-identity)
            (.ref (.ref value 'admission-contract) 'identity))
       (element? PooFlowClassificationEvidence (.ref value 'classification))
       (list? (.ref value 'obligation-evidence))
       (equal? (.ref value 'candidate)
               (.ref (.ref value 'classification) 'candidate))
       (equal? (.ref value 'context)
               (.ref (.ref value 'classification) 'context))
       (eq? (.ref value 'accepted?)
            (and (.ref (.ref value 'classification) 'accepted?)
                 (null? (.ref value 'obligation-evidence))))))

;;; Evidence type: accepts only validation receipts with the required typed slots.
(define-type (PooFlowValidationEvidence @ Type.)
  .element?: poo-flow-validation-evidence-element?)

;; : (-> Object Object Boolean [Alist] Object PooFlowClassificationEvidence)
(def (poo-flow-classification-evidence type-identity-value candidate-value
                                        accepted-value diagnostics-value
                                        context-value)
  (.o kind: 'poo-flow.type.classification-evidence
      type-identity: type-identity-value
      candidate: candidate-value
      accepted?: (if accepted-value #t #f)
      diagnostics: diagnostics-value
      context: context-value))

;; : (-> Object Boolean)
(def (poo-flow-classification-evidence? value)
  (element? PooFlowClassificationEvidence value))

;; : (-> PooFlowClassificationEvidence Boolean)
(def (poo-flow-classification-evidence-accepted? evidence)
  (and (poo-flow-classification-evidence? evidence)
       (.ref evidence 'accepted?)))

;; : (-> PooFlowClassificationEvidence Alist)
(def (poo-flow-classification-evidence->alist evidence)
  (unless (poo-flow-classification-evidence? evidence)
    (raise-type-error PooFlowClassificationEvidence evidence))
  (list (cons 'kind (.ref evidence 'kind))
        (cons 'type-identity (.ref evidence 'type-identity))
        (cons 'accepted? (.ref evidence 'accepted?))
        (cons 'diagnostics (.ref evidence 'diagnostics))
        (cons 'context (.ref evidence 'context))))

;; The single evidence producer records its actual descriptor, including failure
;; rows. Symbolic names remain a diagnostic/wire projection, not object identity.
;; : (-> PooFlowContract Object PooFlowClassificationEvidence [Alist] Boolean [Alist] Object PooFlowValidationEvidence)
(def (poo-flow-validation-evidence contract-value candidate-value
                                    classification-value obligation-evidence-value
                                    accepted-value diagnostics-value context-value)
  (.o kind: 'poo-flow.contract.validation-evidence
      contract-identity: (.ref contract-value 'identity)
      admission-contract: contract-value
      candidate: candidate-value
      classification: classification-value
      obligation-evidence: obligation-evidence-value
      accepted?: (if accepted-value #t #f)
      diagnostics: diagnostics-value
      context: context-value))

;; : (-> Object Boolean)
(def (poo-flow-validation-evidence? value)
  (element? PooFlowValidationEvidence value))

;; : (-> PooFlowValidationEvidence Boolean)
(def (poo-flow-validation-evidence-accepted? evidence)
  (and (poo-flow-validation-evidence? evidence)
       (.ref evidence 'accepted?)))

;; : (-> PooFlowValidationEvidence Alist)
(def (poo-flow-validation-evidence->alist evidence)
  (unless (poo-flow-validation-evidence? evidence)
    (raise-type-error PooFlowValidationEvidence evidence))
  (list (cons 'kind (.ref evidence 'kind))
        (cons 'contract-identity (.ref evidence 'contract-identity))
        (cons 'accepted? (.ref evidence 'accepted?))
        (cons 'classification
              (poo-flow-classification-evidence->alist
               (.ref evidence 'classification)))
        (cons 'obligation-evidence (.ref evidence 'obligation-evidence))
        (cons 'diagnostics (.ref evidence 'diagnostics))
        (cons 'context (.ref evidence 'context))))

;; PooFlowType. makes classification the primary operation.  element? and
;; validate remain the upstream Type protocol and are derived from one
;; evidence-bearing classification decision.
;; : (-> PooFlowType Object Boolean)
(def (poo-flow-type-element? type candidate)
  (poo-flow-classification-evidence-accepted?
   (poo-flow-type-classify type candidate #f)))

;; : (-> PooFlowType Object Object)
(def (poo-flow-type-validate type candidate)
  (let (evidence (poo-flow-type-classify type candidate #f))
    (if (poo-flow-classification-evidence-accepted? evidence)
      candidate
      (raise-type-error type candidate (.ref evidence 'diagnostics)))))

;;; Typeclass boundary: derive element and validation behavior from one classification protocol.
(define-type (PooFlowType. @ Type. identity .classify)
  .element?: (cut poo-flow-type-element? @ <>)
  .validate: (cut poo-flow-type-validate @ <>))

;; A Contract is a Type refinement.  Domain values are validated by a Contract;
;; they never inherit from it.  Obligations are pure and return a list of
;; diagnostic facts; an empty list means that every obligation was discharged.
;; : (-> Object Object [Alist])
(def (poo-flow-contract-empty-obligations _candidate _context)
  '())

;; : (-> PooFlowContract Object Object PooFlowValidationEvidence)
(def (poo-flow-contract-admit-evidence contract candidate context)
  (let* ((value-contract (.ref contract 'value-contract))
         (candidate (if value-contract (validate value-contract candidate) candidate))
         (classification
          (poo-flow-type-classify contract candidate context))
         (_checked
          (unless (and (poo-flow-classification-evidence? classification)
                       (equal? candidate (.ref classification 'candidate))
                       (equal? context (.ref classification 'context)))
            (raise-type-error PooFlowClassificationEvidence classification)))
         (classification-ok?
          (poo-flow-classification-evidence-accepted? classification))
         (responsibilities (.ref contract 'responsibilities))
         (children
          (if classification-ok?
            (map (cut poo-flow-responsibility-evidence
                      candidate context responsibilities <>)
                 (.all-slots responsibilities))
            '()))
         (rejections
          (filter (lambda (child)
                    (not (poo-flow-validation-evidence-accepted? child))) children))
         (obligation-evidence
          (if (and classification-ok? (null? rejections))
            (let* ((local (poo-flow-contract-obligations contract candidate context))
                   (platform (context-contract-obligations context contract candidate)))
              (append local platform))
            '()))
         (failures (append rejections obligation-evidence))
         (diagnostics
          (append (.ref classification 'diagnostics)
                  failures)))
    (.cc (poo-flow-validation-evidence
           contract candidate classification failures
           (and classification-ok? (null? failures)) diagnostics context)
      'responsibility-evidence children)))

;; : (-> PooFlowContract Object Boolean)
(def (poo-flow-contract-element? contract candidate)
  (let (value-contract (.ref contract 'value-contract))
    (and (or (not value-contract) (element? value-contract candidate))
         (poo-flow-validation-evidence-accepted?
          (poo-flow-contract-admit contract candidate #f)))))

;; : (-> PooFlowContract Object Object)
(def (poo-flow-contract-validate contract candidate)
  (let (evidence (poo-flow-contract-admit contract candidate #f))
    (if (poo-flow-validation-evidence-accepted? evidence)
      (.ref evidence 'candidate)
      (raise-type-error contract candidate (.ref evidence 'diagnostics)))))

;;; Contract algebra: combine classification with pure obligations into one admission receipt.
(define-type (PooFlowContract. @ PooFlowType.
                               identity value-contract responsibilities .classify .obligations .admit)
  ;; Optional public POO Type. The single producer normalizes once before
  ;; contextual classification; its result is the evidence/publication subject.
  value-contract: #f
  ;; Contextual child Contracts, not a duplicate map of public field Types.
  ;; Ordinary value responsibilities belong to value-contract/ObjectContract.
  responsibilities: (.o)
  .obligations: poo-flow-contract-empty-obligations
  .admit: (cut poo-flow-contract-admit-evidence @ <> <>)
  .element?: (cut poo-flow-contract-element? @ <>)
  .validate: (cut poo-flow-contract-validate @ <>))

;; : (-> Symbol Procedure Procedure)
(def (poo-flow-predicate-classifier identity predicate)
  (lambda (candidate context)
    (let (accepted? (predicate candidate))
      (poo-flow-classification-evidence
       identity
       candidate
       accepted?
       (if accepted?
         '()
         (list
          (.o kind: 'poo-flow.type.classification-failure
              type-identity: identity
              reason: 'predicate-rejected)))
       context))))

;;; Predicate Types specialize the upstream boolean protocol without weakening
;;; POO refinement. A descriptor extended with a different classifier falls
;;; back to the evidence path, so `.cc` keeps one authoritative semantic
;;; decision while unrefined primitive checks avoid receipt allocation.
;; : (-> PooFlowPredicateType Object Boolean)
(def (poo-flow-predicate-type-element? type candidate)
  (if (eq? (.ref type '.classify)
           (.ref type '.predicate-classify))
    ((.ref type '.predicate) candidate)
    (poo-flow-type-element? type candidate)))

(define-type (PooFlowPredicateType. @ PooFlowType.
                                    identity
                                    .classify
                                    .predicate
                                    .predicate-classify)
  .element?: (cut poo-flow-predicate-type-element? @ <>))

;; : (-> Symbol Procedure PooFlowType)
(def (poo-flow-predicate-type identity predicate)
  (let (classifier (poo-flow-predicate-classifier identity predicate))
    (.cc PooFlowPredicateType.
         'identity identity
         '.classify classifier
         '.predicate predicate
         '.predicate-classify classifier
         'sexp identity)))

;; : (-> Symbol Procedure Procedure PooFlowContract)
(def (poo-flow-predicate-contract identity predicate obligations)
  (.cc PooFlowContract.
       'identity identity
       '.classify (poo-flow-predicate-classifier identity predicate)
       '.obligations obligations
       'sexp identity))

;;; Object responsibility admission delegates every slot to its native Contract.
;;; The map is a POO value; inherited map slots follow upstream precedence.
(def (poo-flow-responsibility-evidence candidate context responsibilities slot)
  (if (.slot? candidate slot)
    (let* ((descriptor (.ref responsibilities slot))
           (value (.ref candidate slot))
           (evidence (poo-flow-contract-admit descriptor value context)))
      ;; Normalization belongs to the public root value Contract. Contextual
      ;; admission must describe that root's actual child, not a detached rewrite.
      (unless (eq? value (.ref evidence 'candidate))
        (raise-type-error descriptor value
          (list (.o kind: 'contextual-child-replaced responsibility: slot))))
      (.cc evidence 'responsibility slot))
    (let (classification
          (poo-flow-classification-evidence
           (.ref (.ref responsibilities slot) 'identity) #f #f
           (list (.o kind: 'missing-responsibility responsibility: slot)) context))
      (.cc (poo-flow-validation-evidence
            (.ref responsibilities slot) #f classification '()
            #f (.ref classification 'diagnostics) context)
           'responsibility slot))))

;;; Domain declarations inherit this native prototype-aware responsibility contract.
(def (poo-flow-native-classify identity proto candidate context)
  (let (accepted?
        (and (object? candidate)
             (if (memq proto (compute-precedence-list! candidate)) #t #f)))
    (poo-flow-classification-evidence
     identity candidate accepted?
     (if accepted? '()
       (list (.o kind: 'prototype-mismatch type-identity: identity))) context)))

;;; Invariant: native objects must prove prototype ancestry before slot obligations run.
(define-type (PooFlowNativeObjectContract. @ PooFlowContract.
                                         identity proto)
  .classify: (cut poo-flow-native-classify identity proto <> <>))
