;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Agentic AI Lab domain specialization of standard gerbil-poo types.
;;; Invariant: gerbil-poo owns primitive Type validation and prototype dispatch;
;;; this module owns only evidence-bearing Agentic AI Lab classification/contracts.

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
                 raise-type-error)
        (only-in :std/list/list every)
)

(export YuanxuType.
        YuanxuContract.
        YuanxuObjectContract.
        YuanxuClassificationEvidence
        YuanxuValidationEvidence
        yuanxu-predicate-type
        yuanxu-predicate-contract
        yuanxu-type-classify
        yuanxu-contract-obligations
        yuanxu-contract-admit
        yuanxu-classification-evidence
        yuanxu-classification-evidence?
        yuanxu-classification-evidence-accepted?
        yuanxu-classification-evidence->alist
        yuanxu-validation-evidence
        yuanxu-validation-evidence?
        yuanxu-validation-evidence-accepted?
        yuanxu-validation-evidence->alist)

;; Open POO protocols dispatch through descriptor slots.  They are intentionally
;; sparse: fixed accessors and final receipt encoders remain ordinary functions.
(.defgeneric (yuanxu-type-classify type candidate context)
  slot: .classify)

;;; Protocol boundary: obligation dispatch stays on the contract descriptor.
(.defgeneric (yuanxu-contract-obligations contract candidate context)
  slot: .obligations)

;;; Protocol boundary: admission returns evidence rather than a bare boolean.
(.defgeneric (yuanxu-contract-admit contract candidate context)
  slot: .admit)

;; : (-> Object Symbol [Symbol] Boolean)
(def (yuanxu-evidence-object? value expected-kind required-slots)
  (and (object? value)
       (every (cut .slot? value <>) required-slots)
       (eq? (.ref value 'kind) expected-kind)
       (boolean? (.ref value 'accepted?))
       (list? (.ref value 'diagnostics))))

;; : (-> Object Boolean)
(def (yuanxu-type-identity? value)
  (or (symbol? value)
      (and (pair? value)
           (list? value)
           (every yuanxu-type-identity? value))))

;; : (-> Object Boolean)
(def (yuanxu-classification-evidence-element? value)
  (and (yuanxu-evidence-object?
        value 'yuanxu.type.classification-evidence
        '(kind type-identity candidate accepted? diagnostics context))
       (yuanxu-type-identity? (.ref value 'type-identity))))

;;; Evidence type: accepts only classification receipts with the required typed slots.
(define-type (YuanxuClassificationEvidence @ Type.)
  .element?: yuanxu-classification-evidence-element?)

;; : (-> Object Boolean)
(def (yuanxu-validation-evidence-element? value)
  (and (yuanxu-evidence-object?
        value 'yuanxu.contract.validation-evidence
        '(kind contract-identity candidate classification obligation-evidence
               accepted? diagnostics context))
       (symbol? (.ref value 'contract-identity))
       (element? YuanxuClassificationEvidence (.ref value 'classification))
       (list? (.ref value 'obligation-evidence))
       (equal? (.ref value 'candidate)
               (.ref (.ref value 'classification) 'candidate))
       (equal? (.ref value 'context)
               (.ref (.ref value 'classification) 'context))
       (eq? (.ref value 'accepted?)
            (and (.ref (.ref value 'classification) 'accepted?)
                 (null? (.ref value 'obligation-evidence))))))

;;; Evidence type: accepts only validation receipts with the required typed slots.
(define-type (YuanxuValidationEvidence @ Type.)
  .element?: yuanxu-validation-evidence-element?)

;; : (-> Object Object Boolean [Alist] Object YuanxuClassificationEvidence)
(def (yuanxu-classification-evidence type-identity-value candidate-value
                                        accepted-value diagnostics-value
                                        context-value)
  (.o kind: 'yuanxu.type.classification-evidence
      type-identity: type-identity-value
      candidate: candidate-value
      accepted?: (if accepted-value #t #f)
      diagnostics: diagnostics-value
      context: context-value))

;; : (-> Object Boolean)
(def (yuanxu-classification-evidence? value)
  (element? YuanxuClassificationEvidence value))

;; : (-> YuanxuClassificationEvidence Boolean)
(def (yuanxu-classification-evidence-accepted? evidence)
  (and (yuanxu-classification-evidence? evidence)
       (.ref evidence 'accepted?)))

;; : (-> YuanxuClassificationEvidence Alist)
(def (yuanxu-classification-evidence->alist evidence)
  (unless (yuanxu-classification-evidence? evidence)
    (raise-type-error YuanxuClassificationEvidence evidence))
  (list (cons 'kind (.ref evidence 'kind))
        (cons 'type-identity (.ref evidence 'type-identity))
        (cons 'accepted? (.ref evidence 'accepted?))
        (cons 'diagnostics (.ref evidence 'diagnostics))
        (cons 'context (.ref evidence 'context))))

;; : (-> Symbol Object YuanxuClassificationEvidence [Alist] Boolean [Alist] Object YuanxuValidationEvidence)
(def (yuanxu-validation-evidence contract-identity-value candidate-value
                                    classification-value obligation-evidence-value
                                    accepted-value diagnostics-value context-value)
  (.o kind: 'yuanxu.contract.validation-evidence
      contract-identity: contract-identity-value
      candidate: candidate-value
      classification: classification-value
      obligation-evidence: obligation-evidence-value
      accepted?: (if accepted-value #t #f)
      diagnostics: diagnostics-value
      context: context-value))

;; : (-> Object Boolean)
(def (yuanxu-validation-evidence? value)
  (element? YuanxuValidationEvidence value))

;; : (-> YuanxuValidationEvidence Boolean)
(def (yuanxu-validation-evidence-accepted? evidence)
  (and (yuanxu-validation-evidence? evidence)
       (.ref evidence 'accepted?)))

;; : (-> YuanxuValidationEvidence Alist)
(def (yuanxu-validation-evidence->alist evidence)
  (unless (yuanxu-validation-evidence? evidence)
    (raise-type-error YuanxuValidationEvidence evidence))
  (list (cons 'kind (.ref evidence 'kind))
        (cons 'contract-identity (.ref evidence 'contract-identity))
        (cons 'accepted? (.ref evidence 'accepted?))
        (cons 'classification
              (yuanxu-classification-evidence->alist
               (.ref evidence 'classification)))
        (cons 'obligation-evidence (.ref evidence 'obligation-evidence))
        (cons 'diagnostics (.ref evidence 'diagnostics))
        (cons 'context (.ref evidence 'context))))

;; YuanxuType. makes classification the primary operation.  element? and
;; validate remain the upstream Type protocol and are derived from one
;; evidence-bearing classification decision.
;; : (-> YuanxuType Object Boolean)
(def (yuanxu-type-element? type candidate)
  (yuanxu-classification-evidence-accepted?
   (yuanxu-type-classify type candidate #f)))

;; : (-> YuanxuType Object Object)
(def (yuanxu-type-validate type candidate)
  (let (evidence (yuanxu-type-classify type candidate #f))
    (if (yuanxu-classification-evidence-accepted? evidence)
      candidate
      (raise-type-error type candidate (.ref evidence 'diagnostics)))))

;;; Typeclass boundary: derive element and validation behavior from one classification protocol.
(define-type (YuanxuType. @ Type. identity .classify)
  .element?: (cut yuanxu-type-element? @ <>)
  .validate: (cut yuanxu-type-validate @ <>))

;; A Contract is a Type refinement.  Domain values are validated by a Contract;
;; they never inherit from it.  Obligations are pure and return a list of
;; diagnostic facts; an empty list means that every obligation was discharged.
;; : (-> Object Object [Alist])
(def (yuanxu-contract-empty-obligations _candidate _context)
  '())

;; : (-> YuanxuContract Symbol Object Object YuanxuValidationEvidence)
(def (yuanxu-contract-admit-evidence contract identity candidate context)
  (let* ((classification
          (yuanxu-type-classify contract candidate context))
         (_checked
          (unless (and (yuanxu-classification-evidence? classification)
                       (equal? candidate (.ref classification 'candidate))
                       (equal? context (.ref classification 'context)))
            (raise-type-error YuanxuClassificationEvidence classification)))
         (classification-ok?
          (yuanxu-classification-evidence-accepted? classification))
         (obligation-evidence
          (if classification-ok?
            (yuanxu-contract-obligations contract candidate context)
            '()))
         (obligations-ok? (null? obligation-evidence))
         (diagnostics
          (append (.ref classification 'diagnostics)
                  obligation-evidence)))
    (yuanxu-validation-evidence
     identity
     candidate
     classification
     obligation-evidence
     (and classification-ok? obligations-ok?)
     diagnostics
     context)))

;; : (-> YuanxuContract Object Boolean)
(def (yuanxu-contract-element? contract candidate)
  (yuanxu-validation-evidence-accepted?
   (yuanxu-contract-admit contract candidate #f)))

;; : (-> YuanxuContract Object Object)
(def (yuanxu-contract-validate contract candidate)
  (let (evidence (yuanxu-contract-admit contract candidate #f))
    (if (yuanxu-validation-evidence-accepted? evidence)
      candidate
      (raise-type-error contract candidate (.ref evidence 'diagnostics)))))

;;; Contract algebra: combine classification with pure obligations into one admission receipt.
(define-type (YuanxuContract. @ YuanxuType.
                               identity .classify .obligations .admit)
  .obligations: yuanxu-contract-empty-obligations
  .admit: (cut yuanxu-contract-admit-evidence @ identity <> <>)
  .element?: (cut yuanxu-contract-element? @ <>)
  .validate: (cut yuanxu-contract-validate @ <>))

;; : (-> Symbol Procedure Procedure)
(def (yuanxu-predicate-classifier identity predicate)
  (lambda (candidate context)
    (let (accepted? (predicate candidate))
      (yuanxu-classification-evidence
       identity
       candidate
       accepted?
       (if accepted?
         '()
         (list
          (.o kind: 'yuanxu.type.classification-failure
              type-identity: identity
              reason: 'predicate-rejected)))
       context))))

;;; Predicate Types specialize the upstream boolean protocol without weakening
;;; POO refinement. A descriptor extended with a different classifier falls
;;; back to the evidence path, so `.cc` keeps one authoritative semantic
;;; decision while unrefined primitive checks avoid receipt allocation.
;; : (-> YuanxuPredicateType Object Boolean)
(def (yuanxu-predicate-type-element? type candidate)
  (if (eq? (.ref type '.classify)
           (.ref type '.predicate-classify))
    ((.ref type '.predicate) candidate)
    (yuanxu-type-element? type candidate)))

(define-type (YuanxuPredicateType. @ YuanxuType.
                                    identity
                                    .classify
                                    .predicate
                                    .predicate-classify)
  .element?: (cut yuanxu-predicate-type-element? @ <>))

;; : (-> Symbol Procedure YuanxuType)
(def (yuanxu-predicate-type identity predicate)
  (let (classifier (yuanxu-predicate-classifier identity predicate))
    (.cc YuanxuPredicateType.
         'identity identity
         '.classify classifier
         '.predicate predicate
         '.predicate-classify classifier
         'sexp identity)))

;; : (-> Symbol Procedure Procedure YuanxuContract)
(def (yuanxu-predicate-contract identity predicate obligations)
  (.cc YuanxuContract.
       'identity identity
       '.classify (yuanxu-predicate-classifier identity predicate)
       '.obligations obligations
       'sexp identity))

;;; Object responsibility admission delegates every slot to its native Contract.
;;; The map is a POO value; inherited map slots follow upstream precedence.
(def (yuanxu-responsibility-evidence candidate context responsibilities slot)
  (if (.slot? candidate slot)
    (.cc (yuanxu-contract-admit (.ref responsibilities slot)
                                (.ref candidate slot) context)
         'responsibility slot)
    (let (classification
          (yuanxu-classification-evidence
           (.ref (.ref responsibilities slot) 'identity) #f #f
           (list (.o kind: 'missing-responsibility responsibility: slot)) context))
      (.cc (yuanxu-validation-evidence
            (.ref (.ref responsibilities slot) 'identity) #f classification '()
            #f (.ref classification 'diagnostics) context)
           'responsibility slot))))

(def (yuanxu-object-admit descriptor candidate context)
  (let* ((classification (yuanxu-type-classify descriptor candidate context))
         (_checked
          (unless (and (yuanxu-classification-evidence? classification)
                       (eq? (.ref descriptor 'identity)
                            (.ref classification 'type-identity))
                       (equal? candidate (.ref classification 'candidate))
                       (equal? context (.ref classification 'context)))
            (raise-type-error YuanxuClassificationEvidence classification)))
         (responsibilities (.ref descriptor 'responsibilities))
         (evidence
          (if (yuanxu-classification-evidence-accepted? classification)
            (map (cut yuanxu-responsibility-evidence
                      candidate context responsibilities <>)
                 (.all-slots responsibilities))
            '()))
         (rejections
          (filter (lambda (item)
                    (not (yuanxu-validation-evidence-accepted? item))) evidence))
         (obligations
          (if (and (yuanxu-classification-evidence-accepted? classification)
                   (null? rejections))
            (yuanxu-contract-obligations descriptor candidate context)
            '()))
         (failures (append rejections obligations)))
    (.cc (yuanxu-validation-evidence
          (.ref descriptor 'identity) candidate classification failures
          (and (yuanxu-classification-evidence-accepted? classification)
               (null? failures))
          (append (.ref classification 'diagnostics) failures) context)
         'responsibility-evidence evidence)))

;;; Protocol boundary: responsibility admission walks the descriptor-owned slot map.
(define-type (YuanxuResponsibilityContract. @ YuanxuContract. responsibilities)
  .admit: (cut yuanxu-object-admit @ <> <>))

;;; Domain declarations inherit this native prototype-aware responsibility contract.
(def (yuanxu-native-classify identity proto candidate context)
  (let (accepted?
        (and (object? candidate)
             (if (memq proto (compute-precedence-list! candidate)) #t #f)))
    (yuanxu-classification-evidence
     identity candidate accepted?
     (if accepted? '()
       (list (.o kind: 'prototype-mismatch type-identity: identity))) context)))

;;; Invariant: native objects must prove prototype ancestry before slot obligations run.
(define-type (YuanxuObjectContract. @ YuanxuResponsibilityContract.
                                         identity proto)
  .classify: (cut yuanxu-native-classify identity proto <> <>))
