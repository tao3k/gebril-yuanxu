;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: shared POO observation and feedback evidence object protocol.
;;; Invariant: diagnostics and receipts are Scheme-side evidence products;
;;; runtime manifests and proof rows are projections, not semantic owners.

(import (only-in :clan/poo/object .def .o .ref object?)
        (only-in :clan/poo/mop .defgeneric validate)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit)
        (only-in :yuanxu/object-family/syntax defpoo-object-family)
        :yuanxu/observability/funcs
        (only-in :yuanxu/observability/types
                 YuanxuObservationIdentityContract YuanxuObservationProvenanceContract
                 YuanxuObservationContextContract YuanxuAdmissionObservationContract
                 yuanxu-observability-diagnostic-contract?
                 yuanxu-observability-receipt-contract?
                 yuanxu-observability-require-diagnostic!
                 yuanxu-observability-require-receipt!))

(export yuanxu-observability-event-prototype
        yuanxu-admission-observation-prototype
        yuanxu-observation-identity
        yuanxu-observation-provenance
        yuanxu-observation-context
        yuanxu-observe-admission-evidence
        yuanxu-observe-contract-admission
        yuanxu-observation-explain
        yuanxu-observation-summary
        yuanxu-observability-span-prototype
        yuanxu-observability-diagnostic-prototype
        yuanxu-observability-receipt-prototype
        yuanxu-observability-projection-prototype
        +yuanxu-observability-object-families+
        yuanxu-observability-family?
        yuanxu-observability-prototype?
        yuanxu-observability-prototype-id
        yuanxu-observability-prototype->alist
        yuanxu-observability-diagnostic?
        yuanxu-observability-diagnostic-family
        yuanxu-observability-diagnostic-severity
        yuanxu-observability-diagnostic-boundary
        yuanxu-observability-diagnostic-validator
        yuanxu-observability-diagnostic-node
        yuanxu-observability-diagnostic-edge
        yuanxu-observability-diagnostic-reason
        yuanxu-observability-diagnostic-message
        yuanxu-observability-diagnostic-repair-target
        yuanxu-observability-diagnostic-artifacts
        yuanxu-observability-diagnostic-record
        yuanxu-observability-diagnostic-code
        yuanxu-observability-diagnostic->alist
        yuanxu-observability-receipt?
        yuanxu-observability-receipt-family
        yuanxu-observability-receipt-schema
        yuanxu-observability-receipt-source
        yuanxu-observability-receipt-graph
        yuanxu-observability-receipt-diagnostics
        yuanxu-observability-receipt-repair
        yuanxu-observability-receipt-readiness
        yuanxu-observability-receipt-artifacts
        yuanxu-observability-receipt-record
        yuanxu-observability-receipt-valid?
        yuanxu-observability-receipt-diagnostic-codes
        yuanxu-observability-receipt-next-action
        yuanxu-observability-graph
        yuanxu-observability-repair
        yuanxu-observability-readiness
        yuanxu-observability-feedback-receipt
        yuanxu-observability-domain-next-action
        yuanxu-observability-agent-feedback
        yuanxu-observability-receipt->alist)

(def ObservationIdentity.
  (.ref YuanxuObservationIdentityContract 'proto))
(def ObservationProvenance.
  (.ref YuanxuObservationProvenanceContract 'proto))
(def ObservationContext.
  (.ref YuanxuObservationContextContract 'proto))
(def AdmissionObservation.
  (.ref YuanxuAdmissionObservationContract 'proto))

;; +yuanxu-observability-object-families+
;;   : [Symbol]
;;   | doc m%
;;       Canonical observability object families. Module-specific diagnostics
;;       extend these families instead of adding central string-only cases.
;;     %
(def +yuanxu-observability-object-families+
  '(observability/event
    observability/span
    observability/diagnostic
    observability/receipt
    observability/projection))

;; : (POOObject Symbol Symbol [Symbol] [Symbol])
(.def yuanxu-observability-event-prototype
  id: 'observability/event
  boundary: 'observability
  owns: '(atomic-evidence state-change validation-fact projection-fact)
  requires: '(source-provenance evidence-kind))

;; : (POOObject Symbol Symbol [Symbol] [Symbol])
(.def yuanxu-observability-span-prototype
  id: 'observability/span
  boundary: 'observability
  owns: '(bounded-operation graph-rebuild validator-run projection-run)
  requires: '(source-provenance start-event end-event))

;; : (POOObject Symbol Symbol [Symbol] [Symbol])
(.def yuanxu-observability-diagnostic-prototype
  id: 'observability/diagnostic
  boundary: 'observability
  owns: '(validator-owned-rejection graph-positioned-finding repair-target)
  requires: '(severity validator reason repair-target))

;; : (POOObject Symbol Symbol [Symbol] [Symbol])
(.def yuanxu-observability-receipt-prototype
  id: 'observability/receipt
  boundary: 'observability
  owns: '(agent-feedback graph-diagnostics repair-readiness drill-down-artifacts)
  requires: '(graph diagnostics repair readiness))

;; : (POOObject Symbol Symbol [Symbol] [Symbol])
(.def yuanxu-observability-projection-prototype
  id: 'observability/projection
  boundary: 'observability
  owns: '(doctor-report graph-preview proof-preview runtime-preview)
  requires: '(producer source-receipt projection-kind))

;; : (-> YuanxuObservabilityFamilyCandidate Boolean)
(def (yuanxu-observability-family? family)
  (and (symbol? family)
       (member family +yuanxu-observability-object-families+)
       #t))

;; : (-> YuanxuObservabilityPrototypeCandidate Boolean)
(def (yuanxu-observability-prototype? value)
  (and (object? value)
       (with-catch
        (lambda (_failure) #f)
        (lambda ()
          (yuanxu-observability-family? (.ref value 'id))))))

;; : (-> YuanxuObservabilityPrototype Symbol)
(def (yuanxu-observability-prototype-id prototype)
  (.ref prototype 'id))

;; : (-> YuanxuObservabilityPrototype Alist)
(def (yuanxu-observability-prototype->alist prototype)
  (list
   (cons 'id (.ref prototype 'id))
   (cons 'boundary (.ref prototype 'boundary))
   (cons 'owns (.ref prototype 'owns))
   (cons 'requires (.ref prototype 'requires))))

;; : (-> Symbol Symbol Symbol YuanxuGraphNodeRef YuanxuGraphEdgeRef Symbol String YuanxuRepairTarget [Alist] YuanxuObservabilityDiagnostic)
(def (yuanxu-observability-diagnostic-record severity boundary validator node edge reason message repair-target . maybe-artifacts)
  (let ((prototype yuanxu-observability-diagnostic-prototype)
        (severity-value severity)
        (boundary-value boundary)
        (validator-value validator)
        (node-value node)
        (edge-value edge)
        (reason-value reason)
        (message-value message)
        (repair-target-value repair-target)
        (artifacts-value (if (null? maybe-artifacts) '() (car maybe-artifacts))))
    (yuanxu-observability-require-diagnostic!
     (.o (:: @ [prototype])
         family: 'observability/diagnostic
         severity: severity-value
         boundary: boundary-value
         validator: validator-value
         node: node-value
         edge: edge-value
         reason: reason-value
         message: message-value
         repair-target: repair-target-value
         artifacts: artifacts-value))))

(def (yuanxu-observability-diagnostic? value)
  (yuanxu-observability-diagnostic-contract? value))

(defpoo-object-family
  (accessors
   (yuanxu-observability-diagnostic-family family)
   (yuanxu-observability-diagnostic-severity severity)
   (yuanxu-observability-diagnostic-boundary boundary)
   (yuanxu-observability-diagnostic-validator validator)
   (yuanxu-observability-diagnostic-node node)
   (yuanxu-observability-diagnostic-edge edge)
   (yuanxu-observability-diagnostic-reason reason)
   (yuanxu-observability-diagnostic-message message)
   (yuanxu-observability-diagnostic-repair-target repair-target)
   (yuanxu-observability-diagnostic-artifacts artifacts))
  (projections))

;; : (-> YuanxuObservabilityDiagnostic Symbol)
(def (yuanxu-observability-diagnostic-code diagnostic)
  (yuanxu-observability-diagnostic-reason diagnostic))

;; : (-> YuanxuObservabilityDiagnostic Alist)
(def (yuanxu-observability-diagnostic->alist diagnostic)
  (list
   (cons 'family (yuanxu-observability-diagnostic-family diagnostic))
   (cons 'severity (yuanxu-observability-diagnostic-severity diagnostic))
   (cons 'boundary (yuanxu-observability-diagnostic-boundary diagnostic))
   (cons 'validator (yuanxu-observability-diagnostic-validator diagnostic))
   (cons 'node (yuanxu-observability-diagnostic-node diagnostic))
   (cons 'edge (yuanxu-observability-diagnostic-edge diagnostic))
   (cons 'reason (yuanxu-observability-diagnostic-reason diagnostic))
   (cons 'message (yuanxu-observability-diagnostic-message diagnostic))
   (cons 'repair-target
         (yuanxu-observability-diagnostic-repair-target diagnostic))
   (cons 'artifacts
         (yuanxu-observability-diagnostic-artifacts diagnostic))))

;; : (-> String YuanxuSourceRef Alist [YuanxuObservabilityDiagnostic] Alist Alist [Alist] YuanxuObservabilityReceipt)
(def (yuanxu-observability-receipt-record schema source graph diagnostics repair readiness . maybe-artifacts)
  (let ((prototype yuanxu-observability-receipt-prototype)
        (schema-value schema)
        (source-value source)
        (graph-value graph)
        (diagnostics-value diagnostics)
        (repair-value repair)
        (readiness-value readiness)
        (artifacts-value (if (null? maybe-artifacts) '() (car maybe-artifacts))))
    (yuanxu-observability-require-receipt!
     (.o (:: @ [prototype])
         family: 'observability/receipt
         schema: schema-value
         source: source-value
         graph: graph-value
         diagnostics: diagnostics-value
         repair: repair-value
         readiness: readiness-value
         artifacts: artifacts-value))))

(def (yuanxu-observability-receipt? value)
  (yuanxu-observability-receipt-contract? value))

(defpoo-object-family
  (accessors
   (yuanxu-observability-receipt-family family)
   (yuanxu-observability-receipt-schema schema)
   (yuanxu-observability-receipt-source source)
   (yuanxu-observability-receipt-graph graph)
   (yuanxu-observability-receipt-diagnostics diagnostics)
   (yuanxu-observability-receipt-repair repair)
   (yuanxu-observability-receipt-readiness readiness)
   (yuanxu-observability-receipt-artifacts artifacts))
  (projections))

;; : (-> YuanxuObservabilityReceipt Boolean)
(def (yuanxu-observability-receipt-valid? receipt)
  (and (yuanxu-observability-receipt? receipt)
       (null? (yuanxu-observability-receipt-diagnostics receipt))
       (eq? (cdr (assq 'state (yuanxu-observability-receipt-readiness receipt)))
            'ready)))

;; : (-> YuanxuObservabilityReceipt [Symbol])
(def (yuanxu-observability-receipt-diagnostic-codes receipt)
  (map yuanxu-observability-diagnostic-code
       (yuanxu-observability-receipt-diagnostics receipt)))

;; : (-> YuanxuObservabilityReceipt Symbol)
(def (yuanxu-observability-receipt-next-action receipt)
  (if (yuanxu-observability-receipt-valid? receipt)
    'accept-graph
    'repair-graph))

;; : (-> Symbol YuanxuGraphSummary [Alist] Alist)
(def (yuanxu-observability-graph kind summary . maybe-metadata)
  (list
   (cons 'kind kind)
   (cons 'summary summary)
   (cons 'metadata
         (if (null? maybe-metadata) '() (car maybe-metadata)))))

;; : (-> (Or Symbol False) (Or Symbol False) [Alist] Alist)
(def (yuanxu-observability-repair target-layer repair-target . maybe-hints)
  (list
   (cons 'target-layer target-layer)
   (cons 'repair-target repair-target)
   (cons 'hints
         (if (null? maybe-hints) '() (car maybe-hints)))))

;; : (-> Symbol Boolean [Alist] Alist)
(def (yuanxu-observability-readiness state valid? . maybe-metadata)
  (list
   (cons 'state state)
   (cons 'valid? valid?)
   (cons 'metadata
         (if (null? maybe-metadata) '() (car maybe-metadata)))))

;; : (-> String YuanxuSourceRef Alist [YuanxuObservabilityDiagnostic] Alist Alist [Alist] YuanxuObservabilityReceipt)
(def (yuanxu-observability-feedback-receipt schema source graph diagnostics repair readiness . maybe-artifacts)
  (yuanxu-observability-receipt-record
   schema
   source
   graph
   diagnostics
   repair
   readiness
   (if (null? maybe-artifacts) '() (car maybe-artifacts))))

;; : (-> Boolean Symbol Symbol Symbol)
(def (yuanxu-observability-domain-next-action valid? accept-action repair-action)
  (if valid? accept-action repair-action))

;; : (-> Symbol Symbol Symbol YuanxuObservabilityReceipt Alist)
(def (yuanxu-observability-agent-feedback kind accept-action repair-action receipt)
  (cons
   (cons 'kind kind)
   (cons
    (cons 'next-action
          (yuanxu-observability-domain-next-action
           (yuanxu-observability-receipt-valid? receipt)
           accept-action
           repair-action))
    (yuanxu-observability-receipt->alist receipt))))

;; : (forall (a) (-> YuanxuObservabilityReceipt (List (Pair Symbol a))))
;; : (-> YuanxuObservabilityReceipt Alist)
(def (yuanxu-observability-receipt->alist receipt)
  (list
   (cons 'family (yuanxu-observability-receipt-family receipt))
   (cons 'schema (yuanxu-observability-receipt-schema receipt))
   (cons 'source (yuanxu-observability-receipt-source receipt))
   (cons 'graph (yuanxu-observability-receipt-graph receipt))
   (cons 'diagnostics
         (map yuanxu-observability-diagnostic->alist
              (yuanxu-observability-receipt-diagnostics receipt)))
   (cons 'diagnostic-codes
         (yuanxu-observability-receipt-diagnostic-codes receipt))
   (cons 'repair (yuanxu-observability-receipt-repair receipt))
   (cons 'readiness (yuanxu-observability-receipt-readiness receipt))
   (cons 'next-action
         (yuanxu-observability-receipt-next-action receipt))
   (cons 'artifacts (yuanxu-observability-receipt-artifacts receipt))))

;;; Boundary: native framework behavior is resolved by upstream slots,
;;; not the legacy metadata-family catalog or an event-kind switch.
(.defgeneric (yuanxu-observation-explain observation) slot: .explain)
;;; Boundary: summary dispatch shares the same native observation receiver contract.
(.defgeneric (yuanxu-observation-summary observation) slot: .summary)

(def yuanxu-admission-observation-prototype
  (.o (:: self AdmissionObservation.)
      (.explain (yuanxu-observation-admission-explanation self))
      (.summary (yuanxu-observation-admission-summary self))))

(def (yuanxu-observation-identity namespace-value name-value revision-value)
  (validate YuanxuObservationIdentityContract
    (.o (:: @ ObservationIdentity.)
        namespace: namespace-value name: name-value revision: revision-value)))

(def (yuanxu-observation-provenance producer-value provider-value phase-value)
  (validate YuanxuObservationProvenanceContract
    (.o (:: @ ObservationProvenance.)
        producer: producer-value provider: provider-value phase: phase-value)))

;;; Identity/provenance are supplied explicitly by the producer. They provide
;;; correlation, not a cryptographic assertion of producer authority.
(def (yuanxu-observation-context identity-value source-value generation-value
                                   causes-value provenance-value
                                   detail-budget: (budget-value 256))
  (validate YuanxuObservationContextContract
    (.o (:: @ ObservationContext.)
        identity: identity-value source: source-value generation: generation-value
        causes: causes-value provenance: provenance-value detail-budget: budget-value)))

(def (yuanxu-observe-admission-evidence context receipt)
  (let ((facts-value (yuanxu-observation-admission-facts receipt context))
        (identity-value (.ref context 'identity))
        (source-value (.ref context 'source))
        (generation-value (.ref context 'generation))
        (causes-value (.ref context 'causes))
        (provenance-value (.ref context 'provenance)))
    (validate YuanxuAdmissionObservationContract
      (.o (:: @ yuanxu-admission-observation-prototype)
          identity: identity-value source: source-value generation: generation-value
          causes: causes-value provenance: provenance-value
          disclosure: 'internal evidence: facts-value))))

(def (yuanxu-observe-contract-admission context contract candidate
                                         evaluation-context: (evaluation-context #f))
  ;; Validate observation metadata before evaluating the subject exactly once.
  (validate YuanxuObservationContextContract context)
  (yuanxu-observe-admission-evidence
   context (yuanxu-contract-admit contract candidate evaluation-context)))
