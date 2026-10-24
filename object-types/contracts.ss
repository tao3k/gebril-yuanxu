;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Yuanxu domain specialization of standard gerbil-poo types.
;;; Invariant: gerbil-poo owns primitive Type validation and prototype dispatch;
;;; this module owns only evidence-bearing Yuanxu classification/contracts.

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
        (only-in :yuanxu/object-family/read-projection
                 owned-read-leaf! owned-read-copy! owned-read-open!)
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
        yuanxu-context-contract-obligations
        yuanxu-contract-admit
        call-with-contract-analysis-root
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

;; Optional platform policy; domain Contract identity and own methods stay intact.
(.defgeneric (yuanxu-context-contract-obligations context contract candidate)
  slot: .contract-obligations)

;; Only the kernel's explicit responsibility edge may request analysis. The
;; pending edge is consumed before classification or any replaceable callback;
;; an independent .admit inside an obligation cannot inherit this permission.
(defstruct contract-analysis (contract candidate context child?))
(def current-contract-analysis (make-parameter #f))
(def (call-with-contract-analysis-root contract candidate context action)
  (parameterize ((current-contract-analysis
                  (make-contract-analysis contract candidate context #f)))
    (action)))

(.defgeneric (context-responsibility-obligations context contract candidate)
  slot: .responsibility-obligations)

(def (context-contract-obligations context contract candidate (analysis? #f))
  (if (and (object? context) (.slot? context '.contract-obligations))
    (let (issues
           (begin
             ;; Open platform callbacks retain the entire original call trace.
             (owned-read-open!)
             (if (and analysis? (.slot? context '.responsibility-obligations))
               (context-responsibility-obligations context contract candidate)
               (yuanxu-context-contract-obligations context contract candidate))))
      (unless (list? issues) (error "Context contract obligations must return diagnostics"))
      issues)
    '()))

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
        '(kind contract-identity admission-contract candidate classification obligation-evidence
               accepted? diagnostics context))
       (symbol? (.ref value 'contract-identity))
       (object? (.ref value 'admission-contract))
       (.slot? (.ref value 'admission-contract) 'identity)
       (eq? (.ref value 'contract-identity)
            (.ref (.ref value 'admission-contract) 'identity))
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
                                        accepted-value diagnostics-value context-value)
  (owned-read-leaf!
    (.o kind: 'yuanxu.type.classification-evidence
        type-identity: type-identity-value
        candidate: candidate-value
        accepted?: (if accepted-value #t #f)
        diagnostics: diagnostics-value
        context: context-value)))

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

;; The single evidence producer records its actual descriptor, including failure
;; rows. Symbolic names remain a diagnostic/wire projection, not object identity.
;; : (-> YuanxuContract Object YuanxuClassificationEvidence [Alist] Boolean [Alist] Object YuanxuValidationEvidence)
(def (yuanxu-validation-evidence contract-value candidate-value
                                    classification-value obligation-evidence-value
                                    accepted-value diagnostics-value context-value)
  (owned-read-leaf!
    (.o kind: 'yuanxu.contract.validation-evidence
        contract-identity: (.ref contract-value 'identity)
        admission-contract: contract-value
        candidate: candidate-value
        classification: classification-value
        obligation-evidence: obligation-evidence-value
        accepted?: (if accepted-value #t #f)
        diagnostics: diagnostics-value
        context: context-value)))

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

;; : (-> YuanxuContract Object Object YuanxuValidationEvidence)
(def (yuanxu-contract-admit-evidence contract candidate context)
  (def pending (current-contract-analysis))
  (def owned?
    (and pending
         (eq? contract (contract-analysis-contract pending))
         (eq? candidate (contract-analysis-candidate pending))
         (eq? context (contract-analysis-context pending))))
  ;; Consume, rather than temporarily hide, this one-shot edge. An .admit
  ;; override calling its inherited producer a second time must be independent.
  (current-contract-analysis #f)
  (contract-admit-evidence contract candidate context owned?
    (and owned? (contract-analysis-child? pending))))

(def (contract-admit-evidence contract candidate context owned? analysis?)
  (let* ((value-contract (.ref contract 'value-contract))
         (consume (cut contextual-contract-admit-evidence contract <> context owned? analysis?)))
    ;; Native Type validation owns recursive Function normalization. Contextual
    ;; admission consumes its actual result once, after the analysis edge was
    ;; consumed above. No runtime import, wrapper or successful value is cached.
    (if value-contract (consume (validate value-contract candidate))
        (consume candidate))))

(def (contextual-contract-admit-evidence contract candidate context owned? analysis?)
  (let* ((classification
          (yuanxu-type-classify contract candidate context))
         (_checked
          (unless (and (yuanxu-classification-evidence? classification)
                       (equal? candidate (.ref classification 'candidate))
                       (equal? context (.ref classification 'context)))
            (raise-type-error YuanxuClassificationEvidence classification)))
         (classification-ok?
          (yuanxu-classification-evidence-accepted? classification))
         (responsibilities (.ref contract 'responsibilities))
         (children
          (if classification-ok?
            (map (cut yuanxu-responsibility-evidence
                      candidate context responsibilities <> owned?)
                 (.all-slots responsibilities))
            '()))
         (rejections
          (filter (lambda (child)
                    (not (yuanxu-validation-evidence-accepted? child))) children))
         (obligation-evidence
          (if (and classification-ok? (null? rejections))
            (let* ((_closed (unless (eq? (.ref contract '.obligations)
                                         yuanxu-contract-empty-obligations)
                              (owned-read-open!)))
                   (local (yuanxu-contract-obligations contract candidate context))
                   (platform (context-contract-obligations context contract candidate analysis?)))
              (append local platform))
            '()))
         (failures (append rejections obligation-evidence))
         (diagnostics
          (append (.ref classification 'diagnostics)
                  failures)))
    (let (evidence (yuanxu-validation-evidence
                    contract candidate classification failures
                    (and classification-ok? (null? failures)) diagnostics context))
      (owned-read-copy! evidence (.cc evidence 'responsibility-evidence children)))))

;; : (-> YuanxuContract Object Boolean)
(def (yuanxu-contract-element? contract candidate)
  (let (value-contract (.ref contract 'value-contract))
    (and (or (not value-contract) (element? value-contract candidate))
         (yuanxu-validation-evidence-accepted?
          (yuanxu-contract-admit contract candidate #f)))))

;; : (-> YuanxuContract Object Object)
(def (yuanxu-contract-validate contract candidate)
  (let (evidence (yuanxu-contract-admit contract candidate #f))
    (if (yuanxu-validation-evidence-accepted? evidence)
      (.ref evidence 'candidate)
      (raise-type-error contract candidate (.ref evidence 'diagnostics)))))

;;; Contract algebra: combine classification with pure obligations into one admission receipt.
(define-type (YuanxuContract. @ YuanxuType.
                               identity value-contract responsibilities .classify .obligations .admit)
  ;; Optional public POO Type. The single producer normalizes once before
  ;; contextual classification; its result is the evidence/publication subject.
  value-contract: #f
  ;; Contextual child Contracts, not a duplicate map of public field Types.
  ;; Ordinary value responsibilities belong to value-contract/ObjectContract.
  responsibilities: (.o)
  ;; The native value Type already owns shape, normalization and refinements.
  ;; Domains do not repeat a success classifier just to project its receipt.
  .classify: (cut yuanxu-classification-evidence identity <> #t '() <>)
  .obligations: yuanxu-contract-empty-obligations
  .admit: (cut yuanxu-contract-admit-evidence @ <> <>)
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
(def (yuanxu-predicate-contract identity predicate
       (obligations yuanxu-contract-empty-obligations))
  (.cc YuanxuContract.
       'identity identity
       '.classify (yuanxu-predicate-classifier identity predicate)
       '.obligations obligations
       'sexp identity))

;;; Object responsibility admission delegates every slot to its native Contract.
;;; The map is a POO value; inherited map slots follow upstream precedence.
(def (yuanxu-responsibility-evidence candidate context responsibilities slot owned?)
  (if (.slot? candidate slot)
    (let* ((descriptor (.ref responsibilities slot))
           (value (.ref candidate slot))
           (evidence
            (parameterize ((current-contract-analysis
                            (and owned? (make-contract-analysis descriptor value context #t))))
              (yuanxu-contract-admit descriptor value context))))
      ;; Normalization belongs to the public root value Contract. Contextual
      ;; admission must describe that root's actual child, not a detached rewrite.
      (unless (eq? value (.ref evidence 'candidate))
        (raise-type-error descriptor value
          (list (.o kind: 'contextual-child-replaced responsibility: slot))))
      (owned-read-copy! evidence (.cc evidence 'responsibility slot)))
    (let (classification
          (yuanxu-classification-evidence
           (.ref (.ref responsibilities slot) 'identity) #f #f
           (list (.o kind: 'missing-responsibility responsibility: slot)) context))
      (let (evidence (yuanxu-validation-evidence
                      (.ref responsibilities slot) #f classification '()
                      #f (.ref classification 'diagnostics) context))
        (owned-read-copy! evidence (.cc evidence 'responsibility slot))))))

;;; Domain declarations inherit this native prototype-aware responsibility contract.
(def (yuanxu-prototype-classify identity proto candidate context)
  (let (accepted?
        (and (object? candidate)
             (if (memq proto (compute-precedence-list! candidate)) #t #f)))
    (yuanxu-classification-evidence
     identity candidate accepted?
     (if accepted? '()
       (list (.o kind: 'prototype-mismatch type-identity: identity))) context)))

;;; Invariant: native objects must prove prototype ancestry before slot obligations run.
(define-type (YuanxuObjectContract. @ YuanxuContract.
                                         identity proto)
  .classify: (cut yuanxu-prototype-classify identity proto <> <>))
