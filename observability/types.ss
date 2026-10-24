;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: native POO type and contract descriptors for observability.
;;; Invariant: validation dispatches through gerbil-poo descriptors; contract
;;; evidence is projected only after the semantic decision has been made.

(import :gerbil/core
        (only-in :clan/poo/object .cc .mix .o .ref .slot? object? object<-alist)
        (only-in :clan/poo/mop define-type element? validate)
        (only-in :yuanxu/object-types/contracts
                 YuanxuContract.
                 YuanxuObjectContract.
                 yuanxu-classification-evidence
                 yuanxu-contract-admit))

(export YuanxuObservabilityDiagnosticContract
        YuanxuObservationIdentityContract
        YuanxuObservationProvenanceContract
        YuanxuObservationContextContract
        YuanxuObservationFailureContract
        YuanxuObservationFactsContract
        YuanxuAdmissionObservationFactsContract
        YuanxuObservationContract
        YuanxuAdmissionObservationContract
        YuanxuObservationSummaryContract
        YuanxuAuthoringObservationContract
        YuanxuDebugCallPolicyContract
        YuanxuDebugCallReceiptContract
        YuanxuDebugSlotPolicyContract
        YuanxuDebugSlotReceiptContract
        YuanxuDebugMemoryPolicyContract
        YuanxuDebugMemorySampleContract
        YuanxuDebugMemoryReceiptContract
        YuanxuDebugDurationReceiptContract
        YuanxuObservabilityReceiptContract
        yuanxu-observability-alist?
        yuanxu-observability-list-of?
        yuanxu-observability-source-ref?
        yuanxu-observability-severity?
        yuanxu-observability-boundary-ref?
        yuanxu-observability-validator-ref?
        yuanxu-observability-graph-node-ref?
        yuanxu-observability-graph-edge-ref?
        yuanxu-observability-reason?
        yuanxu-observability-message?
        yuanxu-observability-repair-target?
        yuanxu-observability-graph-shape?
        yuanxu-observability-repair-shape?
        yuanxu-observability-readiness-shape?
        yuanxu-observability-diagnostic-contract-evidence
        yuanxu-observability-receipt-contract-evidence
        yuanxu-observability-diagnostic-contract?
        yuanxu-observability-receipt-contract?
        yuanxu-observability-require-diagnostic!
        yuanxu-observability-require-receipt!)

(def (yuanxu-observability-alist? value)
  (and (list? value) (andmap pair? value)))

(def (yuanxu-observability-list-of? predicate values)
  (and (list? values) (andmap predicate values)))

(def (yuanxu-observability-source-ref? value)
  (or (symbol? value) (string? value) (yuanxu-observability-alist? value)))

(def (yuanxu-observability-severity? value)
  (and (symbol? value)
       (if (member value '(debug info warning error fatal)) #t #f)))

(def (yuanxu-observability-boundary-ref? value) (symbol? value))
(def (yuanxu-observability-validator-ref? value) (symbol? value))

(def (yuanxu-observability-graph-node-ref? value)
  (or (not value) (symbol? value) (string? value)
      (yuanxu-observability-alist? value)))

(def (yuanxu-observability-graph-edge-ref? value)
  (or (not value) (symbol? value) (string? value) (pair? value)
      (yuanxu-observability-alist? value)))

(def (yuanxu-observability-reason? value) (symbol? value))
(def (yuanxu-observability-message? value) (string? value))

(def (yuanxu-observability-repair-target? value)
  (or (not value) (symbol? value) (string? value)
      (yuanxu-observability-alist? value)))

(def (yuanxu-observability-graph-shape? value)
  (yuanxu-observability-alist? value))

(def (yuanxu-observability-repair-shape? value)
  (and (yuanxu-observability-alist? value)
       (assq 'target-layer value) (assq 'repair-target value) #t))

(def (yuanxu-observability-readiness-shape? value)
  (and (yuanxu-observability-alist? value)
       (assq 'state value) (assq 'valid? value) #t))

(def (yuanxu-observability-object-slots? candidate slots)
  (and (object? candidate)
       (andmap (lambda (slot) (.slot? candidate slot)) slots)))

(def (yuanxu-observability-obligation-failure contract-identity-value
                                                  slot-value expected-value)
  (.o kind: 'yuanxu.contract.obligation-failure
      contract-identity: contract-identity-value
      slot: slot-value
      expected: expected-value))

(def (yuanxu-observability-check-obligation candidate contract-identity
                                                slot predicate expected)
  (if (predicate (.ref candidate slot))
    '()
    (list (yuanxu-observability-obligation-failure
           contract-identity slot expected))))

(def +yuanxu-observability-diagnostic-slots+
  '(family severity boundary validator node edge reason message repair-target artifacts))

(def +yuanxu-observability-receipt-slots+
  '(family schema source graph diagnostics repair readiness artifacts))

(def (yuanxu-observability-classification identity slots candidate context)
  (let (accepted? (yuanxu-observability-object-slots? candidate slots))
    (yuanxu-classification-evidence
     identity candidate accepted?
     (if accepted? '()
         (list (yuanxu-observability-obligation-failure
                identity 'object-shape 'POOObject)))
     context)))

(def (yuanxu-observability-diagnostic-classify candidate context)
  (yuanxu-observability-classification
   'observability/diagnostic
   +yuanxu-observability-diagnostic-slots+
   candidate context))

(def (yuanxu-observability-diagnostic-obligations candidate _context)
  (append
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'family (lambda (value) (eq? value 'observability/diagnostic)) 'observability/diagnostic)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'severity yuanxu-observability-severity? 'ObservabilitySeverity)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'boundary yuanxu-observability-boundary-ref? 'Symbol)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'validator yuanxu-observability-validator-ref? 'Symbol)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'node yuanxu-observability-graph-node-ref? 'GraphNodeRef)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'edge yuanxu-observability-graph-edge-ref? 'GraphEdgeRef)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'reason yuanxu-observability-reason? 'Symbol)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'message yuanxu-observability-message? 'String)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'repair-target yuanxu-observability-repair-target? 'RepairTarget)
   (yuanxu-observability-check-obligation candidate 'observability/diagnostic
    'artifacts yuanxu-observability-alist? 'Alist)))

;;; Diagnostic contract: classification fixes the kind while obligations validate every diagnostic field.
(define-type (YuanxuObservabilityDiagnosticContract @ YuanxuContract.)
  identity: 'observability/diagnostic
  .classify: yuanxu-observability-diagnostic-classify
  .obligations: yuanxu-observability-diagnostic-obligations)

(def (yuanxu-observability-diagnostic-contract? candidate)
  (element? YuanxuObservabilityDiagnosticContract candidate))

(def (yuanxu-observability-diagnostic-contract-evidence candidate)
  (yuanxu-contract-admit
   YuanxuObservabilityDiagnosticContract candidate 'observability))

(def (yuanxu-observability-diagnostic-list? value)
  (yuanxu-observability-list-of?
   yuanxu-observability-diagnostic-contract? value))

(def (yuanxu-observability-receipt-classify candidate context)
  (yuanxu-observability-classification
   'observability/receipt
   +yuanxu-observability-receipt-slots+
   candidate context))

(def (yuanxu-observability-receipt-obligations candidate _context)
  (append
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'family (lambda (value) (eq? value 'observability/receipt)) 'observability/receipt)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'schema string? 'String)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'source yuanxu-observability-source-ref? 'SourceRef)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'graph yuanxu-observability-graph-shape? 'GraphProjection)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'diagnostics yuanxu-observability-diagnostic-list? 'DiagnosticList)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'repair yuanxu-observability-repair-shape? 'RepairProjection)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'readiness yuanxu-observability-readiness-shape? 'ReadinessProjection)
   (yuanxu-observability-check-obligation candidate 'observability/receipt
    'artifacts yuanxu-observability-alist? 'Alist)))

;;; Receipt contract: admission requires graph, diagnostic, repair, readiness, and artifact projections.
(define-type (YuanxuObservabilityReceiptContract @ YuanxuContract.)
  identity: 'observability/receipt
  .classify: yuanxu-observability-receipt-classify
  .obligations: yuanxu-observability-receipt-obligations)

(def (yuanxu-observability-receipt-contract? candidate)
  (element? YuanxuObservabilityReceiptContract candidate))

(def (yuanxu-observability-receipt-contract-evidence candidate)
  (yuanxu-contract-admit
   YuanxuObservabilityReceiptContract candidate 'observability))

(def (yuanxu-observability-require-diagnostic! candidate)
  (validate YuanxuObservabilityDiagnosticContract candidate))

(def (yuanxu-observability-require-receipt! candidate)
  (validate YuanxuObservabilityReceiptContract candidate))

;;; Framework foundation: explicit native prototypes, independent of legacy
;;; feedback receipts and strict module-system presentation structs.
(def (yuanxu-observation-scalar-classify identity predicate candidate context)
  (let (accepted? (predicate candidate))
    (yuanxu-classification-evidence identity candidate accepted?
      (if accepted? '() '(invalid-observation-field)) context)))

;;; Invariant: symbolic observation fields remain closed over Scheme symbols.
(define-type (ObservationSymbol @ YuanxuContract.)
  identity: 'observation/symbol
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/symbol symbol? <> <>))

;;; Invariant: boolean observation fields reject truthy non-boolean values.
(define-type (ObservationBoolean @ YuanxuContract.)
  identity: 'observation/boolean
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/boolean boolean? <> <>))

(def (yuanxu-observation-natural? value)
  (and (exact-integer? value) (>= value 0)))

;;; Invariant: counts and budgets are exact nonnegative integers.
(define-type (ObservationNatural @ YuanxuContract.)
  identity: 'observation/natural
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/natural yuanxu-observation-natural? <> <>))

;;; These owner-local constructors keep dependency primitives out of domain
;;; declarations while returning ordinary native POO values.
;; : (-> Unit POOObject)
(def (yuanxu-observation-empty-prototype) (.o))
;; : (-> Alist POOObject)
(def (yuanxu-observation-contract-shape rows) (object<-alist rows))
;; : (-> POOObject Alist POOObject)
(def (yuanxu-observation-contract-shape/extends base rows)
  (.mix base defaults: rows))
;; : (-> YuanxuContract POOObject)
(def (yuanxu-observation-contract-responsibilities contract)
  (.ref contract 'responsibilities))

;;; Boundary: observable identities bind namespace, name, and revision together.
(define-type (YuanxuObservationIdentityContract @ YuanxuObjectContract.)
  identity: 'observation/identity
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((namespace . ,ObservationSymbol)
     (name . ,ObservationSymbol)
     (revision . ,ObservationSymbol))))

(def (yuanxu-observation-identities? value)
  (yuanxu-observability-list-of?
   (cut element? YuanxuObservationIdentityContract <>) value))

;;; Invariant: causal identity lists contain only admitted native identity objects.
(define-type (ObservationIdentities @ YuanxuContract.)
  identity: 'observation/identities
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/identities yuanxu-observation-identities? <> <>))

;;; Boundary: provenance records producer, provider, and phase without asserting authority.
(define-type (YuanxuObservationProvenanceContract @ YuanxuObjectContract.)
  identity: 'observation/provenance
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((producer . ,YuanxuObservationIdentityContract)
     (provider . ,YuanxuObservationIdentityContract)
     (phase . ,ObservationSymbol))))

;;; Invariant: context keeps identity lineage and its bounded disclosure budget in one value.
(define-type (YuanxuObservationContextContract @ YuanxuObjectContract.)
  identity: 'observation/context
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((identity . ,YuanxuObservationIdentityContract)
     (source . ,YuanxuObservationIdentityContract)
     (generation . ,YuanxuObservationIdentityContract)
     (causes . ,ObservationIdentities)
     (provenance . ,YuanxuObservationProvenanceContract)
     (detail-budget . ,ObservationNatural))))

(def (yuanxu-observation-path? value)
  (yuanxu-observability-list-of? symbol? value))

;;; Invariant: failure paths are structural symbol lists, not presentation strings.
(define-type (ObservationPath @ YuanxuContract.)
  identity: 'observation/path
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/path yuanxu-observation-path? <> <>))

(def (yuanxu-observation-slot-edge? value)
  (and (pair? value)
       (symbol? (car value))
       (symbol? (cdr value))))

(def (yuanxu-observation-slot-path? value)
  (yuanxu-observability-list-of?
   yuanxu-observation-slot-edge? value))

;;; Invariant: a slot path identifies each edge by receiver and slot symbols.
;;; Equal slot names on distinct guarded receivers are not recursive aliases.
(define-type (ObservationSlotPath @ YuanxuContract.)
  identity: 'observation/slot-path
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/slot-path
                  yuanxu-observation-slot-path? <> <>))

;;; Boundary: each failure binds its structural path to a contract and stable code.
(define-type (YuanxuObservationFailureContract @ YuanxuObjectContract.)
  identity: 'observation/failure
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((path . ,ObservationPath)
     (contract . ,ObservationSymbol)
     (code . ,ObservationSymbol))))

(def (yuanxu-observation-failures? value)
  (yuanxu-observability-list-of?
   (cut element? YuanxuObservationFailureContract <>) value))

;;; Invariant: failure collections contain only admitted failure objects.
(define-type (ObservationFailures @ YuanxuContract.)
  identity: 'observation/failures
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/failures yuanxu-observation-failures? <> <>))

;;; Boundary: this empty responsibility base is the native extension point for fact families.
(define-type (YuanxuObservationFactsContract @ YuanxuObjectContract.)
  identity: 'observation/facts
  proto: (yuanxu-observation-empty-prototype)
  responsibilities: (yuanxu-observation-empty-prototype))

(def YuanxuObservationFacts.
  (.ref YuanxuObservationFactsContract 'proto))

(def (yuanxu-admission-facts-obligations value _context)
  (if (and (eq? (.ref value 'accepted?)
                (and (.ref value 'classification-accepted?)
                     (zero? (.ref value 'obligation-count))))
           (or (not (.ref value 'accepted?)) (null? (.ref value 'failures)))
           (or (not (.ref value 'detail-complete?))
               (and (> (.ref value 'inspected-count) 0)
                    (or (.ref value 'accepted?) (pair? (.ref value 'failures)))))
           (>= (.ref value 'inspected-count) (length (.ref value 'failures))))
    '() '(inconsistent-admission-observation)))

;;; Invariant: admission facts must reconcile their decision, counts, and bounded failures.
(define-type (YuanxuAdmissionObservationFactsContract @ YuanxuObservationFactsContract)
  identity: 'observation/admission-facts
  proto: (yuanxu-observation-contract-shape/extends
          YuanxuObservationFacts. '())
  responsibilities:
  (yuanxu-observation-contract-shape
   `((contract . ,ObservationSymbol)
     (accepted? . ,ObservationBoolean)
     (classification-accepted? . ,ObservationBoolean)
     (obligation-count . ,ObservationNatural)
     (failures . ,ObservationFailures)
     (detail-complete? . ,ObservationBoolean)
     (inspected-count . ,ObservationNatural)))
  .obligations: yuanxu-admission-facts-obligations)

(def (yuanxu-observation-internal? value) (eq? value 'internal))
;;; Invariant: the initial framework admits only internal disclosure.
(define-type (ObservationDisclosure @ YuanxuContract.)
  identity: 'observation/disclosure
  .classify: (cut yuanxu-observation-scalar-classify
                  'observation/disclosure yuanxu-observation-internal? <> <>))

;;; Boundary: the event contract binds lineage, disclosure, and native evidence responsibilities.
(define-type (YuanxuObservationContract @ YuanxuObjectContract.)
  identity: 'observation/event
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((identity . ,YuanxuObservationIdentityContract)
     (source . ,YuanxuObservationIdentityContract)
     (generation . ,YuanxuObservationIdentityContract)
     (causes . ,ObservationIdentities)
     (provenance . ,YuanxuObservationProvenanceContract)
     (disclosure . ,ObservationDisclosure)
     (evidence . ,YuanxuObservationFactsContract))))

(def YuanxuObservation.
  (.ref YuanxuObservationContract 'proto))

;;; Invariant: admission events refine the generic evidence slot with admission facts.
(define-type (YuanxuAdmissionObservationContract @ YuanxuObservationContract)
  identity: 'observation/admission-event
  proto: (yuanxu-observation-contract-shape/extends
          YuanxuObservation. '())
  responsibilities:
  ;; Evidence is a refinement, not a fallback default.  A default loses to
  ;; the generic evidence responsibility inherited from the base map and lets
  ;; forged admission facts validate as generic observation facts.
  (.cc (yuanxu-observation-contract-responsibilities
        YuanxuObservationContract)
       'evidence YuanxuAdmissionObservationFactsContract))

;;; Boundary: only bounded aggregate scalars enter the default development renderer.
(define-type (YuanxuObservationSummaryContract @ YuanxuObjectContract.)
  identity: 'observation/summary
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((accepted? . ,ObservationBoolean)
     (detail-complete? . ,ObservationBoolean)
     (failure-count . ,ObservationNatural)
     (inspected-count . ,ObservationNatural))))

;;; Authoring observations are structural advice, not executed runtime facts.
;;; Their fixed phase and rejection polarity prevent a style diagnostic from
;;; being promoted into evidence that a Module or operation actually ran.
(def (yuanxu-authoring-observation-obligations observation _context)
  (if (and
       (or (and (eq? (.ref observation 'form) '.o)
                (eq? (.ref observation 'phase) 'object-construction)
                (eq? (.ref observation 'status) 'inline-prototype-lookup)
                (eq? (.ref observation 'code)
                     'poo-prototype-lookup-inside-composition)
                (eq? (.ref observation 'recommendation)
                     'bind-prototype-once-before-repeated-construction))
           (and (eq? (.ref observation 'form) 'import)
                (eq? (.ref observation 'phase) 'module-admission)
                (eq? (.ref observation 'status) 'aggregate-owner-import)
                (eq? (.ref observation 'code)
                     'module-owner-import-expands-aggregate-facade)
                (eq? (.ref observation 'recommendation)
                     'import-precise-owner))
           (and (eq? (.ref observation 'form) 'import)
                (eq? (.ref observation 'phase) 'build-bootstrap-admission)
                (eq? (.ref observation 'status)
                     'build-bootstrap-imports-package-owner)
                (eq? (.ref observation 'code) 'build-bootstrap-self-import)
                (eq? (.ref observation 'recommendation)
                     'declare-package-spec-only))
           (and (symbol? (.ref observation 'form))
                (eq? (.ref observation 'form) (.ref observation 'owner))
                (eq? (.ref observation 'phase) 'build-bootstrap-admission)
                (eq? (.ref observation 'status)
                     'build-bootstrap-reimplements-package-projection)
                (eq? (.ref observation 'code)
                     'build-bootstrap-parallel-projection)
                (eq? (.ref observation 'recommendation)
                     'declare-public-entry-modules)))
       (not (.ref observation 'accepted?))
       (not (.ref observation 'runtime-executed?)))
    '()
    '(inconsistent-authoring-observation)))

;;; Boundary: source inspection retains only symbolic owner and repair facts.
;;; It never retains the source datum, expanded syntax, object, or slot value.
(define-type (YuanxuAuthoringObservationContract @ YuanxuObjectContract.)
  identity: 'observation/poo-authoring
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((scope . ,ObservationSymbol)
     (owner . ,ObservationSymbol)
     (form . ,ObservationSymbol)
     (phase . ,ObservationSymbol)
     (status . ,ObservationSymbol)
     (code . ,ObservationSymbol)
     (recommendation . ,ObservationSymbol)
     (accepted? . ,ObservationBoolean)
     (runtime-executed? . ,ObservationBoolean)))
  .obligations: yuanxu-authoring-observation-obligations)

;;; Boundary: traced calls carry an explicit depth budget.  The policy is a
;;; native POO value rather than an ambient global tracer setting.
(define-type (YuanxuDebugCallPolicyContract @ YuanxuObjectContract.)
  identity: 'observation/debug-call-policy
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((label . ,ObservationSymbol)
     (maximum-depth . ,ObservationNatural))))

;;; Boundary: call tracing retains only structural identities and categories.
;;; Arguments, results, receivers, and exceptions never enter this receipt.
(define-type (YuanxuDebugCallReceiptContract @ YuanxuObjectContract.)
  identity: 'observation/debug-call-receipt
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((policy . ,YuanxuDebugCallPolicyContract)
     (call . ,ObservationSymbol)
     (depth . ,ObservationNatural)
     (active-path . ,ObservationPath)
     (operator-kind . ,ObservationSymbol)
     (outcome . ,ObservationSymbol)
     (elapsed-nanoseconds . ,ObservationNatural)
     (accepted? . ,ObservationBoolean)
     (reason . ,ObservationSymbol))))

;;; Boundary: lazy slot resolution has its own depth budget.  It is separate
;;; from the call policy because resolving a slot may precede procedure lookup.
;;; Invariant: the budget is positive.  A zero budget would misreport every
;;; first slot lookup as a runtime depth anomaly instead of policy rejection.
(def (yuanxu-debug-slot-policy-obligations policy _context)
  (if (> (.ref policy 'maximum-depth) 0)
    '()
    '(non-positive-maximum-slot-depth)))

;;; Boundary: this Contract owns debug-slot admission configuration only.
;;; A separate call policy cannot silently widen or disable its slot budget.
(define-type (YuanxuDebugSlotPolicyContract @ YuanxuObjectContract.)
  identity: 'observation/debug-slot-policy
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((label . ,ObservationSymbol)
     (maximum-depth . ,ObservationNatural)))
  .obligations: yuanxu-debug-slot-policy-obligations)

;;; Forged slot receipts cannot turn a cycle, excessive depth, or raised
;;; resolver into an accepted observation.  Depth always equals the bounded
;;; active path retained by the receipt.
(def (yuanxu-debug-slot-receipt-obligations receipt _context)
  (let* ((policy (.ref receipt 'policy))
         (receiver (.ref receipt 'receiver))
         (slot (.ref receipt 'slot))
         (edge (cons receiver slot))
         (depth (.ref receipt 'depth))
         (path (.ref receipt 'active-path))
         (outcome (.ref receipt 'outcome)))
    (let-values (((expected-accepted? expected-reason valid-boundary?)
                  (case outcome
                    ((admitted)
                     (values #t 'slot-resolution-admitted
                             (and (not (member edge path))
                                  (< depth (.ref policy 'maximum-depth)))))
                    ((resolved)
                     (values #t 'slot-resolved
                             (and (not (member edge path))
                                  (< depth (.ref policy 'maximum-depth)))))
                    ((raised)
                     (values #f 'slot-resolution-raised
                             (and (not (member edge path))
                                  (< depth (.ref policy 'maximum-depth)))))
                    ((rejected-cycle)
                     (values #f 'recursive-slot-resolution
                             (and (member edge path) #t)))
                    ((rejected-depth)
                     (values #f 'maximum-slot-depth-exceeded
                             (and (not (member edge path))
                                  (>= depth (.ref policy 'maximum-depth)))))
                    (else (values #f 'invalid-slot-outcome #f)))))
      (if (and (= depth (length path))
               valid-boundary?
               (eq? (.ref receipt 'accepted?) expected-accepted?)
               (eq? (.ref receipt 'reason) expected-reason))
        '()
        '(inconsistent-debug-slot-receipt)))))

;;; Boundary: slot receipts retain receiver/slot symbols and an active symbol
;;; path only.  The object, computed value, and original exception stay out.
(define-type (YuanxuDebugSlotReceiptContract @ YuanxuObjectContract.)
  identity: 'observation/debug-slot-receipt
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((policy . ,YuanxuDebugSlotPolicyContract)
     (receiver . ,ObservationSymbol)
     (slot . ,ObservationSymbol)
     (depth . ,ObservationNatural)
     (active-path . ,ObservationSlotPath)
     (outcome . ,ObservationSymbol)
     (accepted? . ,ObservationBoolean)
     (reason . ,ObservationSymbol)))
  .obligations: yuanxu-debug-slot-receipt-obligations)

;;; Boundary: a debug memory policy is an explicit POO value. The process
;;; launcher owns the independent Gambit heap ceiling used before this module
;;; can be loaded.
(define-type (YuanxuDebugMemoryPolicyContract @ YuanxuObjectContract.)
  identity: 'observation/debug-memory-policy
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((label . ,ObservationSymbol)
     (heap-limit-bytes . ,ObservationNatural)
     (live-growth-limit-bytes . ,ObservationNatural)
     (sample-interval-milliseconds . ,ObservationNatural)
     (collect-before-sample? . ,ObservationBoolean)
     (fail-closed? . ,ObservationBoolean))))

;;; Boundary: a sample projects Gerbil runtime counters into a native POO
;;; value; it never retains heap objects or exposes the runtime statistics row.
(define-type (YuanxuDebugMemorySampleContract @ YuanxuObjectContract.)
  identity: 'observation/debug-memory-sample
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((phase . ,ObservationSymbol)
     (heap-size-bytes . ,ObservationNatural)
     (allocated-bytes . ,ObservationNatural)
     (live-bytes . ,ObservationNatural)
     (movable-bytes . ,ObservationNatural)
     (still-bytes . ,ObservationNatural))))

(def (yuanxu-debug-memory-receipt-obligations receipt _context)
  (let* ((policy (.ref receipt 'policy))
         (after (.ref receipt 'after))
         (heap-exceeded?
          (> (.ref after 'heap-size-bytes)
             (.ref policy 'heap-limit-bytes)))
         (growth-exceeded?
          (> (.ref receipt 'live-growth-bytes)
             (.ref policy 'live-growth-limit-bytes)))
         (expected-reason
          (cond (heap-exceeded? 'heap-limit-exceeded)
                (growth-exceeded? 'live-growth-limit-exceeded)
                (else 'within-budget)))
         (expected-accepted?
          (and (not heap-exceeded?) (not growth-exceeded?))))
    (if (and (eq? (.ref receipt 'reason) expected-reason)
             (eq? (.ref receipt 'accepted?) expected-accepted?))
      '()
      '(inconsistent-debug-memory-receipt))))

;;; Invariant: a receipt binds one policy to two samples and a derived verdict.
;;; Negative deltas are normalized to zero by the pure constructor.
(define-type (YuanxuDebugMemoryReceiptContract @ YuanxuObjectContract.)
  identity: 'observation/debug-memory-receipt
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((phase . ,ObservationSymbol)
     (policy . ,YuanxuDebugMemoryPolicyContract)
     (before . ,YuanxuDebugMemorySampleContract)
     (after . ,YuanxuDebugMemorySampleContract)
     (heap-growth-bytes . ,ObservationNatural)
     (live-growth-bytes . ,ObservationNatural)
     (accepted? . ,ObservationBoolean)
     (reason . ,ObservationSymbol)))
  .obligations: yuanxu-debug-memory-receipt-obligations)

;;; Busy loops can exceed a Case duration budget without heap growth.
(define-type (YuanxuDebugDurationReceiptContract @ YuanxuObjectContract.)
  identity: 'observation/debug-duration-receipt
  proto: (yuanxu-observation-empty-prototype)
  responsibilities:
  (yuanxu-observation-contract-shape
   `((phase . ,ObservationSymbol)
     (policy-label . ,ObservationSymbol)
     (limit-milliseconds . ,ObservationNatural)
     (elapsed-milliseconds . ,ObservationNatural)
     (accepted? . ,ObservationBoolean)
     (reason . ,ObservationSymbol))))
