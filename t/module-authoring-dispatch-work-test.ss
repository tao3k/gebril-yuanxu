;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Actual dispatch work and admission-boundary controls; no cache or runner.
(import (only-in :clan/poo/type Record)
        (only-in :std/list/list find)
        :std/test
        (only-in :std/error Error? Error-message)
        (only-in :clan/poo/object .o .get .ref .cc .put! compute-precedence-list! object-protocol-set!
                 object-%instance object-%precedence-list replay-slot-reads!)
        (only-in :clan/poo/mop with-inheritance-hooks)
        (only-in :clan/poo/object .ref/inline)
        (only-in :clan/poo/object .putslot! $constant-slot-spec)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :clan/poo/slot-observation
                 call-with-slot-read-observer slot-read-key slot-read-receiver
                 %call-with-recorded-slot-reads slot-read-observers-compatible? without-observation)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :tao3k/yuanxu/observability/output yuanxu-write-observation-line!)
        (only-in :clan/poo/read-projection
                 call-with-owned-source-reads owned-read-function-scope?)
        (only-in :tao3k/yuanxu/module-system/source/interface yuanxu-module-interface)
        (only-in :tao3k/yuanxu/module-system/authoring/admission
                 ModuleAuthoringAnalysisGeneric ModuleAuthoringAnalysisProtocol
                 YuanxuModuleAuthoringAdmission YuanxuModuleAuthoringDiagnostics
                 yuanxu-module-authoring-role
                 yuanxu-module-authoring-admit-datums
                 yuanxu-module-authoring-source-admit
                 yuanxu-module-authoring-admission-accepted?)
        (only-in :tao3k/yuanxu/module-system/authoring/roles ConfigSourceRole.)
        (only-in :clan/poo/clos/types
                 ClosGenericFunction ClosEffectiveMethod ClosInvocationFrame ClosMethod)
        (only-in :clan/poo/clos/objects %prepare-effective-method)
        (only-in :clan/poo/clos/dispatch
                 poo-clos-call poo-clos-compute-effective-method))
(export module-authoring-dispatch-work-test)

;; Count runtime policy-slot deliveries, including replay. This deliberately
;; does NOT call them predicate executions, allocations or elapsed work.
(def policies
  (list ClosGenericFunction ClosEffectiveMethod ClosInvocationFrame ClosMethod))
(def (policy-deliveries interface count)
  (def counts (make-vector (length policies) 0))
  (call-with-slot-read-observer
    (lambda (read)
      (when (eq? (slot-read-key read) '.element?)
        (let loop ((remaining policies) (index 0))
          (when (pair? remaining)
            (if (eq? (car remaining) (slot-read-receiver read))
              (vector-set! counts index (+ 1 (vector-ref counts index)))
              (loop (cdr remaining) (+ index 1)))))))
    (lambda ()
      (check-equal?
        (yuanxu-module-authoring-admission-accepted?
          (yuanxu-module-authoring-admit-datums
            interface 'objects (make-list count '(def value 1))))
        #t)))
  counts)

(def module-authoring-dispatch-work-test
  (test-suite "Actual authoring dispatch policy work"
    (yuanxu-test-case "default batch avoids carriers but validates every datum"
      (def interface (yuanxu-module-interface "functional-role" (Record) '()))
      ;; Runtime cold argument preparation keeps ordinary dispatch. Warm it
      ;; through the public API before measuring the closed function route.
      (yuanxu-module-authoring-admit-datums interface 'objects '((def First 1)))
      (defvalues (result reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-source-reads
              (lambda () (error "hook-free default unexpectedly opened a source boundary"))
              (lambda ()
                (yuanxu-module-authoring-admit-datums interface 'objects
                  '((def First 1) (def Second 2) (.o add-profile: #t))))))
          unique-roots?: #t))
      (def owners (make-hash-table-eq))
      (for-each (lambda (read) (hash-put! owners (slot-read-receiver read) #t)) reads)
      (def (carriers type)
        (filter (lambda (owner) (and (not (eq? owner (.get type proto)))
                                    (memq (.get type proto) (compute-precedence-list! owner))))
                (hash-keys owners)))
      (check-equal? (length (carriers ClosEffectiveMethod)) 0)
      (check-equal? (length (carriers ClosInvocationFrame)) 0)
      ;; A Function call does not need even the unused carrier Type/prototype
      ;; policies. Collection does not install an observer or change the route.
      (for-each
        (lambda (owner) (check-equal? (hash-key? owners owner) #f))
        (list ClosEffectiveMethod ClosInvocationFrame
              (.get ClosEffectiveMethod proto) (.get ClosInvocationFrame proto)))
      ;; The aggregate is the only admission receiver actually constructed.
      ;; This inspects original read owners, without creating or merging tokens.
      (check-equal?
        (length (filter (lambda (owner)
                          (let (fields (object-%instance owner))
                            (and fields
                              (eq? (hash-get fields 'kind) 'yuanxu.module-authoring.admission))))
                        (hash-keys owners)))
        1)
      (check-equal? (yuanxu-module-authoring-admission-accepted? result) #f)
      (check-equal? (length (.get result diagnostics)) 1)
      ;; Inspect the actual retained issuer graph after analysis. This visitor
      ;; does not wrap dispatch, suppress delivery or manufacture read tokens.
      (def visits 0)
      (replay-slot-reads! reads (lambda (_receiver _key) (set! visits (+ visits 1))))
      (yuanxu-write-observation-line!
        "authoring-closed-support datums=3 roots=%s visits=%s" (length reads) visits))
    (yuanxu-test-case "runtime scope query distinguishes collection and arbitrary callbacks"
      (check-equal? (slot-read-observers-compatible? '()) #t)
      (defvalues (_ reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (check-equal? (slot-read-observers-compatible? '()) #t)
            (call-with-slot-read-observer void
              (lambda ()
                (check-equal? (slot-read-observers-compatible? (list void)) #t)
                (call-with-slot-read-observer (lambda (_) (void))
                  (lambda () (check-equal? (slot-read-observers-compatible? (list void)) #f))))))))
      (check-equal? reads '()))
    (yuanxu-test-case "guarded layout preserves issued records and parent child isolation"
      (def parent (.o port: 5432))
      (def child (.cc parent port: 5433))
      (def site (make-slot-cache 'port))
      (check-equal? (.ref/inline parent site) 5432)
      (defvalues (_first direct)
        (%call-with-recorded-slot-reads (lambda () (.ref parent 'port))))
      (defvalues (_second indexed)
        (%call-with-recorded-slot-reads (lambda () (.ref/inline parent site))))
      (def (port-read reads)
        (car (filter (lambda (read) (and (eq? (slot-read-receiver read) parent)
                                        (eq? (slot-read-key read) 'port))) reads)))
      (check-equal? (eq? (port-read direct) (port-read indexed)) #t)
      (check-equal? (.ref/inline child site) 5433)
      (check-equal? (.ref/inline parent site) 5432)
      (.put! parent 'port 5440)
      (check-equal? (.ref/inline child site) 5433)
      (check-equal? (.ref/inline parent site) 5440))
    (yuanxu-test-case "source prechecks remain active and nested boundaries cannot replace parents"
      (def source (.o port: 5432))
      (def events '())
      (def failure (list 'precheck-refused))
      (def (outer) (set! events (cons 'outer events)))
      (def (inner) (set! events (cons 'inner events)))
      (call-with-owned-source-reads outer
        (lambda ()
          (check-equal? (owned-read-function-scope?) #t)
          (check-equal? (.get source port) 5432)
          (check-equal? events '())
          (object-protocol-set! source (.o))
          (call-with-owned-source-reads inner (lambda () (check-equal? (.get source port) 5432)))
          (check-equal? (reverse events) '(inner outer))
          (set! events '())
          (without-observation
            (lambda ()
              (call-with-owned-source-reads inner (lambda () (check-equal? (.get source port) 5432)))))
          (check-equal? events '(inner))
          (set! events '())
          (check-exception
            (call-with-owned-source-reads (lambda () (raise failure)) (lambda () (.get source port)))
            (lambda (actual) (eq? actual failure)))
          (check-equal? events '())
          (check-equal? (.get source port) 5432)
          (check-equal? events '(outer))))
      (check-equal? (slot-read-observers-compatible? '()) #t))
    (yuanxu-test-case "source prechecks retain cold C3 hooks and invalidation without warm snapshots"
      (def preparations 0)
      (def boundaries 0)
      (def protocol
        (.o (compute-precedence-list
              (lambda (_receiver next)
                (set! preparations (1+ preparations)) (next)))))
      (def source (with-inheritance-hooks protocol (.o port: 5432)))
      (check-equal? (object-%precedence-list source) #f)
      (call-with-owned-source-reads
        (lambda () (set! boundaries (1+ boundaries)))
        (lambda ()
          (check-equal? (.get source port) 5432)
          (def canonical (object-%precedence-list source))
          (def public (compute-precedence-list! source))
          (check-equal? public canonical)
          (check-equal? (eq? public canonical) #f)
          (check-equal? (.get source port) 5432)
          (check-equal? (eq? canonical (object-%precedence-list source)) #t)
          (check-equal? preparations 1)
          ;; A runtime .put! may retain C3. Edit the actual source SlotSpec
          ;; here to exercise runtime metadata invalidation and cold retry.
          (.putslot! source 'port ($constant-slot-spec 5433))
          (check-equal? (object-%precedence-list source) #f)
          (check-equal? (.get source port) 5433)
          (check-equal? preparations 2)
          (object-protocol-set! source
            (.o (compute-precedence-list (lambda (_receiver next) (reverse (next))))))
          (check-exception (.get source port)
            (lambda (cause)
              (and (Error? cause)
                   (equal? (Error-message cause) "inheritance hook must preserve checked C3 order"))))
          (check-equal? (object-%precedence-list source) #f)))
      (check-equal? (> boundaries 0) #t))
    (yuanxu-test-case "warm datum admission still reads nested carrier policies"
      (def interface (yuanxu-module-interface "work-probe" (Record) '()))
      ;; Warm only through the actual operation; never clear or replace Gerbil state.
      (policy-deliveries interface 1)
      (def one (policy-deliveries interface 1))
      (def four (policy-deliveries interface 4))
      (def eight (policy-deliveries interface 8))
      (for-each
        (lambda (index)
          (check-equal? (> (vector-ref one index) 0) #t)
          (check-equal? (vector-ref four index) (* 4 (vector-ref one index)))
          (check-equal? (vector-ref eight index) (* 8 (vector-ref one index))))
        (iota (length policies)))
      (yuanxu-write-observation-line!
        "authoring-policy-deliveries order=generic,effective,frame,method one=%s four=%s eight=%s"
        one four eight))
    (yuanxu-test-case "closed default checks once and an open hook checks before and after"
      (def interface (yuanxu-module-interface "boundary-probe" (Record) '()))
      (def executor (.get interface authoring executor))
      (def role (yuanxu-module-authoring-role interface 'objects))
      (def checks 0)
      (def calls 0)
      (def protocol
        (.cc ModuleAuthoringAnalysisProtocol
          compute-effective-method:
          (lambda (_generic _arguments _methods checked-default)
            ;; This is a passive observation of the actual policy, not a
            ;; replacement validator or a new acceptance mechanism.
            (check-equal? checks 1)
            (set! calls (+ calls 1))
            checked-default)))
      (def open-generic
        (.cc ModuleAuthoringAnalysisGeneric protocol: protocol
          methods: (.get ModuleAuthoringAnalysisGeneric methods)))
      (def (observe read)
        (when (and (eq? (slot-read-receiver read) ClosEffectiveMethod)
                   (eq? (slot-read-key read) '.element?))
          (set! checks (+ 1 checks))))
      (call-with-slot-read-observer observe
        (lambda ()
          (poo-clos-compute-effective-method ModuleAuthoringAnalysisGeneric
            executor role interface '(def value 1))))
      (check-equal? checks 1)
      (set! checks 0)
      (call-with-slot-read-observer observe
        (lambda ()
          (poo-clos-compute-effective-method open-generic
            executor role interface '(def value 1))))
      (check-equal? checks 2)
      (check-equal? calls 1))
    (yuanxu-test-case "a prepared constructor produces a fresh checked carrier on each demand"
      (def interface (yuanxu-module-interface "fresh-carrier" (Record) '()))
      (def arguments
        (list (.get interface authoring executor)
          (yuanxu-module-authoring-role interface 'objects)
          interface '(def value 1)))
      (def effective
        (apply poo-clos-compute-effective-method ModuleAuthoringAnalysisGeneric arguments))
      (def prepare
        (%prepare-effective-method ModuleAuthoringAnalysisGeneric arguments
          (.get effective around) (.get effective before)
          (.get effective primary) (.get effective after)))
      (def first (prepare))
      (.put! first 'arguments #f)
      (def second (prepare))
      (check-equal? (eq? first second) #f)
      (check-equal? (eq? (.get second arguments) arguments) #t))
    (yuanxu-test-case "public effective-method callback may invalidate the checked default"
      (def interface (yuanxu-module-interface "callback-probe" (Record) '()))
      (def calls 0)
      (def protocol
        (.cc ModuleAuthoringAnalysisProtocol
          compute-effective-method:
          (lambda (_generic _arguments _methods checked-default)
            (set! calls (+ calls 1))
            ;; Negative injection at the real public hook boundary. The object
            ;; was checked at construction, but that check is now insufficient.
            (.put! checked-default 'arguments #f)
            checked-default)))
      ;; Runtime copying re-evaluates constructor slots; the registered method
      ;; set is runtime state, not the constructor's empty default. Retain the
      ;; actual descriptors explicitly in this private hook-injection probe.
      (def generic
        (.cc ModuleAuthoringAnalysisGeneric protocol: protocol
          methods: (.get ModuleAuthoringAnalysisGeneric methods)))
      (check-exception
        (poo-clos-call generic (.get interface authoring executor)
          (yuanxu-module-authoring-role interface 'objects)
          interface '(def value 1))
        (lambda (failure)
          (def code (.ref failure 'code))
          (yuanxu-write-observation-line! "authoring-return-probe code=%s calls=%s" code calls)
          (eq? code 'invalid-effective-method-result)))
      (check-equal? calls 1))
    (yuanxu-test-case "source role resolves again after the previous result Type runs"
      (def interface (yuanxu-module-interface "role-return-boundary" (Record) '()))
      (def profile (.get interface authoring))
      (def original (.ref YuanxuModuleAuthoringDiagnostics '.validate))
      (def calls 0)
      (dynamic-wind
        (lambda ()
          (.put! YuanxuModuleAuthoringDiagnostics '.validate
            (lambda (value)
              (set! calls (1+ calls))
              (when (= calls 1) (.put! profile 'objects ConfigSourceRole.))
              (original value))))
        (lambda ()
          (defvalues (accepted? diagnostic)
            (yuanxu-module-authoring-source-admit interface 'objects
              '((def First 1) (stage build))))
          (check-equal? accepted? #f)
          (check-equal? (.get diagnostic code) 'poo-config-must-compose-maintained-values)
          (check-equal? (.get diagnostic role) 'config)
          (check-equal? calls 2))
        (lambda () (.put! YuanxuModuleAuthoringDiagnostics '.validate original))))
    (yuanxu-test-case "closed support retains original Generic declaration and rejects ABA"
      (def interface (yuanxu-module-interface "support-forwarding" (Record) '()))
      (yuanxu-module-authoring-admit-datums interface 'objects '((def Warm 1)))
      (defvalues (result reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (yuanxu-module-authoring-admit-datums interface 'objects
              '((def First 1) (def Second 2))))))
      (check-equal? (yuanxu-module-authoring-admission-accepted? result) #t)
      (def (methods-read? read)
        (and (eq? (slot-read-receiver read) ModuleAuthoringAnalysisGeneric)
             (eq? (slot-read-key read) 'methods)))
      (def published-read (find methods-read? reads))
      (check-equal? (and published-read #t) #t)
      (defvalues (source-result source-reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-values
              (lambda ()
                (yuanxu-module-authoring-source-admit interface 'objects
                  '((def First 1) (def Second 2))))
              list))))
      (check-equal? source-result '(#t #f))
      (check-equal? (eq? published-read (find methods-read? source-reads)) #t)
      (replay-slot-reads! reads void)
      (replay-slot-reads! source-reads void)
      (def methods (.get ModuleAuthoringAnalysisGeneric methods))
      ;; Source policy capture cannot become approval across a later revision,
      ;; even when the exact original method list is restored.
      (dynamic-wind
        (lambda () (.put! ModuleAuthoringAnalysisGeneric 'methods (map values methods)))
        (lambda () (check-exception (replay-slot-reads! reads void) error?))
        (lambda () (.put! ModuleAuthoringAnalysisGeneric 'methods methods)))
      (check-exception (replay-slot-reads! reads void) error?)
      (check-exception (replay-slot-reads! source-reads void) error?)
      ;; Restored live declarations still work via ordinary Generic fallback.
      (check-equal? (yuanxu-module-authoring-admission-accepted?
        (yuanxu-module-authoring-admit-datums interface 'objects '((def Restored 1)))) #t))
    (yuanxu-test-case "source-only admission omits the empty stock receipt and still runs a replaced validator"
      (def interface (yuanxu-module-interface "source-only" (Record) '()))
      (def (source-admit)
        (call-with-values
          (lambda () (yuanxu-module-authoring-source-admit interface 'objects '((def Good 1))))
          list))
      (defvalues (result reads)
        (%call-with-recorded-slot-reads source-admit unique-roots?: #t))
      (check-equal? result '(#t #f))
      (check-equal?
        (ormap (lambda (read)
               (let (owner (slot-read-receiver read))
                 (and (object-%instance owner)
                      (eq? (hash-get (object-%instance owner) 'kind) 'yuanxu.module-authoring.admission))))
             reads)
        #f)
      (check-equal?
        (ormap (lambda (read)
                 (and (eq? (slot-read-receiver read) YuanxuModuleAuthoringAdmission)
                      (eq? (slot-read-key read) '.validate))) reads)
        #t)
      (def original (.ref YuanxuModuleAuthoringAdmission '.validate))
      (def calls 0)
      (dynamic-wind
        (lambda ()
          (.put! YuanxuModuleAuthoringAdmission '.validate
            (lambda (_receipt)
              (set! calls (1+ calls))
              (.o accepted?: #f diagnostics: '(#f)))))
        (lambda ()
          ;; A false diagnostic still belongs to an actual refusal.
          (check-equal? (source-admit) '(#f #f))
          (check-equal? calls 1))
        (lambda () (.put! YuanxuModuleAuthoringAdmission '.validate original))))))
