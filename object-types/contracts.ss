;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Yuanxu domain specialization of standard gerbil-poo types.
;;; Invariant: gerbil-poo owns primitive Type validation and prototype dispatch;
;;; this module owns only evidence-bearing Yuanxu classification/contracts.

(import (runtime: :clan/poo/object)
        (only-in :clan/poo/mop
                 .defgeneric
                 define-type
                 Type
                 Type.
                 Slot instance Bool Object
                 element?
                 TypeError?
                 validate
                 raise-type-error)
        (only-in :clan/poo/object-contract checked-action)
        (only-in :clan/poo/type Record Symbol List)
        (only-in :std/error Error-irritants)
        (only-in :std/list/list every)
        (only-in :yuanxu/object-family/read-projection
                 owned-read-leaf! owned-read-copy! owned-read-open!
                 make-owned-method-check call-with-owned-read-method-checks)
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
        yuanxu-value-admit
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

;; : (-> Object Boolean)
(def (yuanxu-type-identity? value)
  (or (symbol? value)
      (and (pair? value)
           (list? value)
           (every yuanxu-type-identity? value))))

(define-type (EvidenceIdentity @ Type.) .element?: yuanxu-type-identity?)
;; These are required opaque REFERENCES, not configurable untyped data. Slot
;; presence is runtime; normalization must not rewrite either referent. Their
;; relation to classification/publication is checked below and at bind-evidence.
(def EvidenceReferences
  (.o candidate: (instance Slot) context: (instance Slot)))
(.def (YuanxuClassificationEvidence @
        (Record kind: [Symbol constant: 'yuanxu.type.classification-evidence]
                type-identity: [EvidenceIdentity] accepted?: [Bool]
                diagnostics: [(List Object)]))
  slots: =>.+ EvidenceReferences)

(.def (YuanxuValidationEvidence @
        (Record kind: [Symbol constant: 'yuanxu.contract.validation-evidence]
                contract-identity: [Symbol] admission-contract: [Type]
                classification: [YuanxuClassificationEvidence]
                obligation-evidence: [(List Object)] accepted?: [Bool]
                diagnostics: [(List Object)]))
  slots: =>.+ EvidenceReferences
  ;; Only contextual relations remain here; runtime Slot/Record owns shape.
  (.element? (inherited)
    (lambda (value)
      (and (call-with-owned-read-method-checks validation-evidence-method-checks
             (inherited) value)
           (eq? (.get value contract-identity) (.get value admission-contract identity))
           (equal? (.get value candidate) (.get value classification candidate))
           (equal? (.get value context) (.get value classification context))
           (eq? (.get value accepted?)
                (and (.get value classification accepted?)
                     (null? (.get value obligation-evidence))))))))

;; : (-> Object Object Boolean [Alist] Object YuanxuClassificationEvidence)
(def (yuanxu-classification-evidence type-identity candidate accepted-value diagnostics context)
  (def kind 'yuanxu.type.classification-evidence)
  (def accepted? (if accepted-value #t #f))
  (owned-read-leaf!
    (.o bind-these: #f kind type-identity candidate accepted? diagnostics context)))

(def classification-evidence-element (.ref YuanxuClassificationEvidence '.element?))
(def evidence-slot-method-checks
  ;; Native Slot dispatch can select a different descriptor Type. The actual
  ;; selected field checker must be maintained before it receives the Record.
  (list (make-owned-method-check #f '.slot.check (.ref Slot '.slot.check))))
(def validation-evidence-method-checks
  (cons (make-owned-method-check YuanxuClassificationEvidence '.element?
          classification-evidence-element)
        evidence-slot-method-checks))
(def validation-evidence-element (.ref YuanxuValidationEvidence '.element?))
(def (evidence-element? descriptor maintained value)
  (def method (.ref descriptor '.element?))
  ;; An ordinary POO method can retain a receipt without a slot observer or
  ;; an object protocol. Authenticate the open boundary before handing it over.
  (cond
   ((not (eq? method maintained)) (owned-read-open!) (method value))
   ((eq? descriptor YuanxuClassificationEvidence)
    (call-with-owned-read-method-checks evidence-slot-method-checks method value))
   (else (method value))))

;; : (-> Object Boolean)
(def (yuanxu-classification-evidence? value)
  (evidence-element? YuanxuClassificationEvidence classification-evidence-element value))

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
(def (yuanxu-validation-evidence admission-contract candidate classification obligation-evidence
                                accepted-value diagnostics context)
  (def kind 'yuanxu.contract.validation-evidence)
  (def accepted? (if accepted-value #t #f))
  ;; Keep the actual descriptor's identity lookup lazy.
  (owned-read-leaf!
    (.o bind-these: #f kind contract-identity: (.ref admission-contract 'identity)
        admission-contract candidate classification obligation-evidence accepted? diagnostics context)))

;; : (-> Object Boolean)
(def (yuanxu-validation-evidence? value)
  (evidence-element? YuanxuValidationEvidence validation-evidence-element value))

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

;; Named runtime value Types are not contextual Contract adapters. Module
;; publication/scope admission uses this one value path; domain .admit retains
;; its explicit responsibilities and authorization protocol above.
(def (yuanxu-value-admit descriptor candidate context)
  ;; An independent value boundary cannot borrow a pending child permission.
  (current-contract-analysis #f)
  (validate Type descriptor)
  (unless (and (.slot? descriptor 'identity) (symbol? (.get descriptor identity))
               (not (ormap (cut .slot? descriptor <>) '(.classify .obligations .admit))))
    (error "value admission requires a named value Type" descriptor))
  (def revision (object-revision descriptor))
  (let/cc refuse
    (def checked
      (with-catch
        (lambda (cause)
          (if (TypeError? cause)
            (refuse (value-contract-refusal descriptor candidate context cause))
            (raise cause)))
        (cut validate descriptor candidate)))
    ;; Runtime obligations/constraints ran inside validate. Platform policy is
    ;; distinct and must inspect the actual normalized subject, on every call.
    (def obligations (context-contract-obligations context descriptor checked))
    (unless (= revision (object-revision descriptor))
      (error "value Type changed during admission" descriptor))
    (def classification
      (yuanxu-classification-evidence (.get descriptor identity) checked #t '() context))
    (yuanxu-validation-evidence descriptor checked classification obligations
      (null? obligations) obligations context)))

;; Only the runtime VALUE action is inside this refusal boundary. Contextual
;; obligations, source checks and publication callbacks are deliberately outside.
;; Preserve runtime diagnostic objects/paths and the original condition itself.
(def (value-contract-refusal contract candidate context cause)
  (def details (Error-irritants cause))
  (def rejected
    (match details
      ([_where value (? list? _failures)]
       ;; Runtime rebinding derives the checked root from the supplied root.
       ;; A nested validator's child must never replace that root in evidence.
       (if (and (object? candidate) (object? value)
                (memq candidate (compute-precedence-list! value))) value candidate))
      (else candidate)))
  (def issues
    (match details
      ([_where value (? list? failures)]
       (if (and (eq? value rejected) (pair? failures)
                (every (lambda (issue)
                         (and (object? issue) (.slot? issue 'kind) (.slot? issue 'path))) failures))
         failures
         (list (.o kind: 'type-contract-refused path: '() cause: cause))))
      (else (list (.o kind: 'type-contract-refused path: '() cause: cause)))))
  (def classification
    (yuanxu-classification-evidence (.get contract identity) rejected #f issues context))
  (.cc (yuanxu-validation-evidence contract rejected classification '() #f issues context)
    cause: cause))

(def (contract-admit-evidence contract candidate context owned? analysis?)
  ;; Context-only descendants already receive their checked child. A missing
  ;; value Type has no normalization stage: do not materialize its FUN cache.
  (let/cc refuse
    (def checked
      (if (.get contract value-contract)
        ;; Preparation stays outside the handler: an invalid descriptor is a
        ;; programming error. Only this value invocation may escape on refusal.
        (let (action (.get contract prepared-value-action))
          (with-catch
            (lambda (cause)
              (if (TypeError? cause)
                (refuse (value-contract-refusal contract candidate context cause))
                (raise cause)))
            (cut action candidate)))
        candidate))
    (contextual-contract-admit-evidence contract checked context owned? analysis?)))

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
  ;; Runtime FUN composition is prepared on the effective descriptor, not per
  ;; candidate. It validates afresh and returns its actual normalized value.
  prepared-value-action: (if value-contract (checked-action value-contract values) values)
  ;; Contextual child Contracts, not a duplicate map of public field Types.
  ;; Ordinary value responsibilities belong to value-contract/ObjectContract.
  responsibilities: (.o)
  ;; The runtime value Type already owns shape, normalization and refinements.
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

;;; Object responsibility admission delegates every slot to its Contract.
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

;;; Domain declarations inherit this runtime prototype-aware responsibility contract.
(def (yuanxu-prototype-classify identity proto candidate context)
  (let (accepted?
        (and (object? candidate)
             (if (memq proto (compute-precedence-list! candidate)) #t #f)))
    (yuanxu-classification-evidence
     identity candidate accepted?
     (if accepted? '()
       (list (.o kind: 'prototype-mismatch type-identity: identity))) context)))

;;; Invariant: runtime objects must prove prototype ancestry before slot obligations run.
(define-type (YuanxuObjectContract. @ YuanxuContract.
                                         identity proto)
  .classify: (cut yuanxu-prototype-classify identity proto <> <>))
