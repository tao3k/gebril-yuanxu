;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: shared role-aware source admission for one loaded Module Interface.
;;; Invariant: source is read as inert data; this owner never expands or runs it.

(import (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads %record-slot-reads!
                 slot-read-receiver slot-read-value without-observation)
        (only-in :clan/poo/mop Type. define-type element? validate)
        (only-in :clan/poo/type List)
        (only-in :std/list/list any delete-duplicates/hash filter-map find map-in-order)
        (only-in :tao3k/yuanxu/utilities/algorithms
                 yuanxu-read-datums/append-map
                 yuanxu-scheme-datum-find)
        (only-in :tao3k/yuanxu/module-system/source/interface
                 yuanxu-module-interface-prototype
                 yuanxu-module-interface?
                 yuanxu-module-interface-id
                 yuanxu-module-interface-authoring)
        (only-in :tao3k/yuanxu/module-system/observability/presentation
                 yuanxu-poo-slot-authoring-datum-bindings
                 yuanxu-poo-slot-authoring-self-reference?)
        ;; Role admission needs dispatch and immutable method declarations, not
        ;; the aggregate class evolution/reflection/load-form publication.
        (only-in :clan/poo/clos/objects
                 poo-clos-generic-protocol
                 poo-clos-compose-method-bundle
                 clos-call-carrier-policy-guard)
        (only-in :clan/poo/read-projection call-with-owned-read-projection
                 owned-read-function-scope? owned-read-method! owned-read-derived!
                 owned-read-fields-present? make-owned-method-check call-with-owned-read-method-checks)
        (only-in :clan/poo/clos/generic-syntax .defgeneric .defmethod .generic-object)
        (only-in :clan/poo/clos/dispatch poo-clos-compute-applicable-methods)
        (only-in :clan/poo/clos/method-bundle-syntax .defmethod-bundle)
        (only-in :tao3k/yuanxu/module-system/source/observations
                 module-source-object-policy current-module-source-observer
                 module-source-measure-operation)
        (only-in :tao3k/yuanxu/module-system/authoring/roles
                 ModuleAuthoringExecutor. ModuleSourceRole. ConfigSourceRole.
                 TypesSourceRole. ObjectsSourceRole. FunsSourceRole.
                 InterfaceSourceRole. BuildSourceRole.))

(export ModuleAuthoringAnalysisProtocol
        ModuleAuthoringAnalysisGeneric
        ModuleAuthoringCoreMethods
        ModuleAuthoringDiagnostic
        YuanxuModuleAuthoringDiagnostic
        YuanxuModuleAuthoringDiagnostics
        YuanxuModuleAuthoringAdmission
        yuanxu-module-authoring-role
        yuanxu-module-authoring-analyze-datum
        yuanxu-module-authoring-admit-datum
        yuanxu-module-authoring-admit-datums
        yuanxu-module-authoring-source-admit
        yuanxu-module-authoring-admit-port
        call-with-module-authoring-read-scope
        yuanxu-module-authoring-admission?
        yuanxu-module-authoring-admission-accepted?
        yuanxu-module-authoring-admission-diagnostics)

;; Stable receipt identities. Module/source revisions remain owned by their
;; existing publication Metadata and currentness guards, not by kind names.
(.def ModuleAuthoringDiagnostic
  kind: 'yuanxu.module-authoring.diagnostic
  module: #f
  role: #f
  code: #f
  subject: #f
  rule: #f
  recommendation: #f
  repair-operators: '()
  freedom: #f
  runtime-executed?: #f)

(.def ModuleAuthoringAdmission
  kind: 'yuanxu.module-authoring.admission
  module: #f
  role: #f
  accepted?: #f
  diagnostics: '()
  runtime-executed?: #f)

(def (yuanxu-module-authoring-diagnostic-shape? value)
  (and (object? value)
       (andmap (cut .slot? value <>)
               '(kind module role code subject rule recommendation
                      repair-operators freedom runtime-executed?))
       (eq? (.ref value 'kind) 'yuanxu.module-authoring.diagnostic)
       (string? (.ref value 'module))
       (symbol? (.ref value 'role))
       (symbol? (.ref value 'code))
       (symbol? (.ref value 'rule))
       (symbol? (.ref value 'recommendation))
       (list? (.ref value 'repair-operators))
       (andmap symbol? (.ref value 'repair-operators))
       (symbol? (.ref value 'freedom))
       (eq? (.ref value 'runtime-executed?) #f)))

(define-type (YuanxuModuleAuthoringDiagnostic @ Type.)
  .element?: yuanxu-module-authoring-diagnostic-shape?)

;; Analysis validates every datum's result, including contributed results.
;; Admission validates the POO receipt only where that receipt is constructed.
(def YuanxuModuleAuthoringDiagnostics (List YuanxuModuleAuthoringDiagnostic))
(def diagnostics-validation-checks
  (list (make-owned-method-check YuanxuModuleAuthoringDiagnostics '.validate
          (.ref YuanxuModuleAuthoringDiagnostics '.validate))))
(def (validate-authoring-diagnostics value)
  ;; POO checks the actual selected method read before calling a replacement.
  (call-with-owned-read-method-checks diagnostics-validation-checks
    (cut validate YuanxuModuleAuthoringDiagnostics <>) value))

(def (yuanxu-module-authoring-admission-shape? value)
  (and (object? value)
       (owned-read-fields-present? value
         '(kind module role accepted? diagnostics runtime-executed?))
       (eq? (.ref value 'kind) 'yuanxu.module-authoring.admission)
       (string? (.ref value 'module))
       (symbol? (.ref value 'role))
       (boolean? (.ref value 'accepted?))
       (list? (.ref value 'diagnostics))
       (andmap (cut element? YuanxuModuleAuthoringDiagnostic <>)
               (.ref value 'diagnostics))
       (eq? (.ref value 'accepted?)
            (null? (.ref value 'diagnostics)))
       (eq? (.ref value 'runtime-executed?) #f)))

(define-type (YuanxuModuleAuthoringAdmission @ Type.)
  .element?: yuanxu-module-authoring-admission-shape?)

;; : (-> Symbol [Symbol] (Maybe Symbol))
(def (yuanxu-module-authoring-forbidden-slot-verb slot verbs)
  (and (symbol? slot)
       (let* ((name (symbol->string slot))
              (plain (if (string-prefix? "." name)
                       (substring name 1 (string-length name))
                       name)))
         (find (lambda (verb)
                 (string-prefix?
                  (string-append (symbol->string verb) "-")
                  plain))
               verbs))))

;; : (-> PooModuleInterface PooModuleSourceRole Symbol PooModuleAuthoringDiagnostic)
(def (yuanxu-module-authoring-slot-diagnostic interface source-role slot)
  (validate YuanxuModuleAuthoringDiagnostic
    (.o (:: @ ModuleAuthoringDiagnostic)
        module: (yuanxu-module-interface-id interface)
        role: (.ref source-role 'identity)
        code: 'poo-domain-slot-must-be-noun
        subject: slot
        rule: 'poo-slot-algebra-only
        recommendation: 'rename-as-domain-noun-and-refine-runtime-slot
        repair-operators: (.ref source-role 'repair-operators)
        freedom: (.ref source-role 'freedom))))

;; : (-> PooModuleInterface PooModuleSourceRole SchemeDatum [PooModuleAuthoringDiagnostic])
(def (yuanxu-module-authoring-slot-diagnostics interface role bindings)
  (filter-map
   (lambda (binding)
     (and (yuanxu-module-authoring-forbidden-slot-verb
           (car binding)
           (.ref role 'forbidden-slot-verbs))
          (yuanxu-module-authoring-slot-diagnostic
           interface role (car binding))))
   bindings))

;; A lazy POO slot can recurse before runtime observability has a chance to
;; report progress. Reuse the inert-source observation at the admission edge.
(def (yuanxu-module-authoring-self-reference-diagnostics interface role bindings)
  (filter-map
   (lambda (binding)
     (and (yuanxu-poo-slot-authoring-self-reference?
           (car binding) (cdr binding))
          (yuanxu-module-authoring-surface-diagnostic
           interface role
           'poo-slot-initializer-shadows-slot
           (car binding)
           'poo-slot-initializer-must-not-shadow-slot-name
           'rename-local-or-wrap-in-helper)))
   bindings))

;; : (-> SchemeDatum [Symbol] Boolean (Maybe Symbol))
;;; Walk executable child forms, but never reinterpret quoted values or import
;;; leaf symbols as calls.  This catches a hidden (.o ...) under a root
;;; composition without turning the Contract into a Scheme parser/evaluator.
(def (yuanxu-module-authoring-forbidden-root-form datum forbidden recursive?)
  (let (forbidden-form
        (lambda (candidate)
          (and (pair? candidate)
               (symbol? (car candidate))
               (memq (car candidate) forbidden)
               (car candidate))))
    (if recursive?
      (yuanxu-scheme-datum-find forbidden-form datum)
      (forbidden-form datum))))

;; : (-> PooModuleInterface PooModuleSourceRole SchemeDatum [PooModuleAuthoringDiagnostic])
(def (yuanxu-module-authoring-root-diagnostics interface source-role datum)
  (let (form
        (yuanxu-module-authoring-forbidden-root-form
         datum
         (.ref source-role 'forbidden-root-forms)
         (.ref source-role 'recursive-root-forms?)))
    (if form
      (list
       (validate YuanxuModuleAuthoringDiagnostic
         (.o (:: @ ModuleAuthoringDiagnostic)
             module: (yuanxu-module-interface-id interface)
             role: (.ref source-role 'identity)
             code: 'poo-config-must-compose-maintained-values
             subject: form
             rule: 'root-config-composition-only
             recommendation: 'move-responsibility-to-selected-profile-owner
             repair-operators: (.ref source-role 'repair-operators)
             freedom: (.ref source-role 'freedom))))
      '())))

;; : (-> SchemeDatum (Maybe Symbol))
;;; Import wrappers keep the imported module in their second position.  This
;;; reads only the Scheme import datum; it does not expand or evaluate
;;; an alternate module language.
(def (yuanxu-module-authoring-import-module import-spec)
  (cond
   ((symbol? import-spec) import-spec)
   ((and (pair? import-spec)
         (memq (car import-spec)
               '(only-in except-in rename-in prefix-in)))
    (yuanxu-module-authoring-import-module (cadr import-spec)))
   (else #f)))

;; : (-> SchemeDatum [Symbol] (Maybe Symbol))
(def (yuanxu-module-authoring-forbidden-import datum forbidden)
  (and (pair? datum)
       (eq? (car datum) 'import)
       (any (lambda (import-spec)
              (let (module-name
                    (yuanxu-module-authoring-import-module import-spec))
                (and module-name
                     (memq module-name forbidden)
                     module-name)))
            (cdr datum))))

;; : (-> SchemeDatum [Symbol] (Maybe Symbol))
(def (yuanxu-module-authoring-forbidden-form datum forbidden)
  (yuanxu-scheme-datum-find
   (lambda (candidate)
     (and (pair? candidate)
          (symbol? (car candidate))
          (memq (car candidate) forbidden)
          (car candidate)))
   datum))

;; : (-> SchemeDatum Boolean)
(def (yuanxu-module-authoring-raw-behavior-hook? datum)
  (if (yuanxu-scheme-datum-find
       (lambda (candidate)
         (and (pair? candidate)
              (eq? (car candidate) 'lambda)
              (pair? (cdr candidate))
              (equal? (cadr candidate) '(self super))))
       datum)
    #t
    #f))

;;; Query slots are the public semantic boundary, not a place to hide a raw
;;; string/list language or an anonymous evaluator.  Provider-specific source
;;; text remains valid behind a named projection object such as `gql-source`;
;;; only slots that claim Query identity are governed here.
;; : (-> Symbol Boolean)
(def (yuanxu-module-authoring-query-slot? slot)
  (and (symbol? slot)
       (let (name (symbol->string slot))
         (or (member slot '(query queries query-predicate query-predicates))
             (string-suffix? "-query" name)
             (string-suffix? "-queries" name)))))

;; : (-> SchemeDatum Boolean)
(def (yuanxu-module-authoring-raw-query-initializer? initializer)
  (cond
   ((string? initializer) #t)
   ((not (pair? initializer)) #f)
   ((memq (car initializer) '(lambda list vector)) #t)
   ((and (memq (car initializer) '(quote quasiquote))
         (pair? (cdr initializer)))
    (let (quoted (cadr initializer))
      (or (string? quoted) (pair? quoted) (vector? quoted))))
   (else #f)))

;; : (-> PooModuleInterface PooModuleSourceRole SchemeDatum [PooModuleAuthoringDiagnostic])
(def (yuanxu-module-authoring-query-diagnostics interface role bindings)
  (if (.ref role 'forbid-raw-query-initializers?)
    (filter-map
     (lambda (binding)
       (and (yuanxu-module-authoring-query-slot? (car binding))
            (yuanxu-module-authoring-raw-query-initializer? (cdr binding))
            (yuanxu-module-authoring-surface-diagnostic
             interface role
             'poo-query-must-be-poo-object
             (car binding)
             'single-poo-semantic-model
             'bind-named-poo-query-or-provider-projection)))
     bindings)
    '()))

(def (yuanxu-module-authoring-surface-diagnostic
      interface source-role code-value subject-value rule-value
      recommendation-value)
  (validate YuanxuModuleAuthoringDiagnostic
    (.o (:: @ ModuleAuthoringDiagnostic)
        module: (yuanxu-module-interface-id interface)
        role: (.ref source-role 'identity)
        code: code-value
        subject: subject-value
        rule: rule-value
        recommendation: recommendation-value
        repair-operators: (.ref source-role 'repair-operators)
        freedom: (.ref source-role 'freedom))))

;; : (-> PooModuleInterface PooModuleSourceRole SchemeDatum [PooModuleAuthoringDiagnostic])
(def (yuanxu-module-authoring-default-surface-diagnostics interface role datum)
  (let* ((forbidden-import
          (yuanxu-module-authoring-forbidden-import
           datum (.ref role 'forbidden-imports)))
         (forbidden-form
          (yuanxu-module-authoring-forbidden-form
           datum (.ref role 'forbidden-forms)))
         (raw-hook?
          (and (.ref role 'forbid-raw-behavior-hooks?)
               (yuanxu-module-authoring-raw-behavior-hook? datum))))
    (filter-map
     (lambda (rule-row)
       (and (car rule-row)
            (apply yuanxu-module-authoring-surface-diagnostic
                   interface role (cdr rule-row))))
     (list
      (list forbidden-import
            'poo-user-surface-forbids-meta-import forbidden-import
            'default-surface-meta-last
            'move-meta-extension-to-maintained-module-owner)
      (list forbidden-form
            'poo-user-surface-forbids-direct-clos forbidden-form
            'default-surface-value-first
            'select-maintained-profile-or-extension-owner)
      (list raw-hook?
            'poo-user-surface-forbids-raw-behavior-hook 'lambda
            'default-surface-behavior-on-demand
            'move-behavior-to-named-maintained-operation)))))

;; : (-> PooModuleInterface PooModuleSourceRole [PooModuleAuthoringDiagnostic] PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admission interface source-role diagnostic-values)
  (def candidate
    (.o (:: @ ModuleAuthoringAdmission)
        module: (yuanxu-module-interface-id interface)
        role: (.ref source-role 'identity)
        accepted?: (null? diagnostic-values)
        diagnostics: diagnostic-values))
  ;; Only this real factory enrolls the receipt. Live external observation
  ;; keeps the former field-query sequence, including its validation callbacks.
  (validate YuanxuModuleAuthoringAdmission
    (if (owned-read-function-scope?) (owned-read-derived! candidate) candidate)))

(def (yuanxu-module-authoring-diagnostics/common interface role datum)
  (let (bindings (yuanxu-poo-slot-authoring-datum-bindings datum))
     (append
      (yuanxu-module-authoring-slot-diagnostics interface role bindings)
      (yuanxu-module-authoring-self-reference-diagnostics
       interface role bindings)
      (yuanxu-module-authoring-query-diagnostics interface role bindings))))

(def (yuanxu-module-authoring-diagnostics/config interface role datum)
  (let (bindings (yuanxu-poo-slot-authoring-datum-bindings datum))
     (append
      (yuanxu-module-authoring-slot-diagnostics interface role bindings)
      (yuanxu-module-authoring-self-reference-diagnostics
       interface role bindings)
      (yuanxu-module-authoring-query-diagnostics interface role bindings)
      (yuanxu-module-authoring-root-diagnostics interface role datum)
      (yuanxu-module-authoring-default-surface-diagnostics
       interface role datum))))

;;; Executor strategy and SourceRole are independently extensible. Module
;;; packages can contribute a method bundle for a refined executor/role pair
;;; without extending a central role switch.
(def ModuleAuthoringAnalysisProtocol
  (poo-clos-generic-protocol 'module-system/authoring-analysis))

(.defgeneric module-authoring-analyze (executor role interface datum)
  (protocol ModuleAuthoringAnalysisProtocol))

;; Keep the exported generic object: contributor bundles compose with this
;; exact protocol owner, rather than a separately constructed lookalike.
(def ModuleAuthoringAnalysisGeneric
  (.generic-object module-authoring-analyze))

;; One source-level rule owns the shared crossing; normal .defmethod lowering
;; supplies the specializers, lexical frame and lambda-list contract.
(defrules authoring-method ()
  ((_ role-prototype admit)
   (let* ((entry admit)
          (method (.defmethod (module-authoring-analyze
                 (executor (prototype ModuleAuthoringExecutor.))
                 (role (prototype role-prototype))
                 (interface (prototype yuanxu-module-interface-prototype))
                 datum)
                  (entry interface role datum))))
     ;; Both call forms come from this ONE maintained declaration. Contributors
     ;; cannot qualify by adding this field: the issued baseline owns identities.
     (.put! method '%direct-primary entry)
     method)))

(.defmethod-bundle ModuleAuthoringCoreMethods
  ModuleAuthoringAnalysisProtocol
  (authoring-method ModuleSourceRole. yuanxu-module-authoring-diagnostics/common)
  (authoring-method ConfigSourceRole. yuanxu-module-authoring-diagnostics/config))

(poo-clos-compose-method-bundle
 ModuleAuthoringAnalysisGeneric
 ModuleAuthoringCoreMethods)

;; The generated wrappers retain the normal public dispatch boundary. Batch
;; analysis must also construct and validate each invocation: runtime observers
;; may inspect carrier policy reads or contribute effects at those reads.
(def authoring-closed-bodies
  (map (cut .ref <> 'body) (.ref ModuleAuthoringCoreMethods 'methods)))

;; Preserve mutable list/string policy values as well as runtime object
;; revisions. Object leaves retain identity; no read record is synthesized.
(def (copy-policy-payload value)
  (cond ((pair? value) (cons (copy-policy-payload (car value)) (copy-policy-payload (cdr value))))
        ((string? value) (string-copy value))
        (else value)))
(def (same-policy-payload? value snapshot)
  (cond ((pair? snapshot)
         (and (pair? value) (same-policy-payload? (car value) (car snapshot))
              (same-policy-payload? (cdr value) (cdr snapshot))))
        ((string? snapshot) (and (string? value) (string=? value snapshot)))
        (else (eqv? value snapshot))))

;; Issue Function profiles from the real generic's declared prototype methods.
;; Native C4 still determines applicability for EACH real argument row. These
;; are method values, not invocation or admission results.
(defvalues (default-function-profiles default-method-reads)
  (%call-with-recorded-slot-reads
    (lambda ()
      (for-each
        (lambda (method) (.ref method 'body) (.ref method '%direct-primary))
        (.ref ModuleAuthoringCoreMethods 'methods))
      (map
        (lambda (role)
          (let (methods
                 (poo-clos-compute-applicable-methods ModuleAuthoringAnalysisGeneric
                   ModuleAuthoringExecutor. role yuanxu-module-interface-prototype #f))
            (cons role (and (pair? methods) (car methods)))))
        (list ConfigSourceRole. ModuleSourceRole.)))
    unique-roots?: #t))
(def default-method-payloads
  (map (lambda (read) (cons read (copy-policy-payload (slot-read-value read)))) default-method-reads))
(def default-method-trace
  ;; Ask POO for its original ordered deliveries once. The trace contains
  ;; no chosen method or approval, and the receiver projection is only
  ;; topology. The native guard still authenticates every signed record.
  (without-observation
    (lambda ()
      (with-catch (lambda (_unsupported) #f)
        (lambda ()
          (defvalues (_ reads)
            (%call-with-recorded-slot-reads
              (lambda () (reobserve-slot-reads! default-method-reads))))
          (and (pair? reads)
               (cons reads
                     (delete-duplicates/hash (map slot-read-receiver reads)
                       table: (make-hash-table-eq) from-end?: #t))))))))
(def (plain-dispatch-argument? value)
  ;; Inspect only warm runtime metadata. No cold getter or logical class bridge
  ;; may open a callback before ordinary Generic fallback owns that operation.
  (and (object? value) (object-%precedence-list value) (not (object-protocol value))))
;; Two fixed access sites over the two maintained descriptors, NOT one layout
;; per selected Module. Runtime .ref/inline retains revision/receiver guards,
;; original read delivery and its ordinary lazy miss path.
;; The producer's demand-filled layout retains full runtime preparation and read
;; authentication. These sites consume only the chosen body/primary; eagerly
;; filling every unrelated descriptor value is not part of role admission.
;; Open/changed carriers retain the Generic branch below.
(def authoring-body-site (make-slot-cache 'body))
(def authoring-primary-site (make-slot-cache '%direct-primary))
(def stock-source-roles
  (list TypesSourceRole. ObjectsSourceRole. FunsSourceRole.
        ConfigSourceRole. InterfaceSourceRole. BuildSourceRole.))
(def stock-role-policy-current?
  (module-source-object-policy
    (append stock-source-roles
            (list YuanxuModuleAuthoringDiagnostics YuanxuModuleAuthoringDiagnostic
                  ModuleAuthoringDiagnostic yuanxu-module-interface-prototype))))
(def (invoke-function-method method interface role datum)
  (let ((body (.ref/inline method authoring-body-site))
        (primary (.ref/inline method authoring-primary-site)))
    ;; Capture the body before the open guard can retarget the invocation.
    (owned-read-method! body method)
    (primary interface role datum)))
(def (default-function-method executor role interface)
  ;; The authenticated default methods have identical executor/interface/any
  ;; axes. Only the role's native C4 position distinguishes their specificity.
  ;; Walking C4, rather than profile declaration order, retains multiple-parent
  ;; precedence. Unknown axes/method state still use the public Generic below.
  (and (memq ModuleAuthoringExecutor. (object-%precedence-list executor))
       (memq yuanxu-module-interface-prototype (object-%precedence-list interface))
       (any (lambda (parent)
              (let (profile (assq parent default-function-profiles))
                (and profile (cdr profile))))
            (object-%precedence-list role))))
(def (current-default-method executor role interface)
  (and (plain-dispatch-argument? executor)
       (plain-dispatch-argument? role)
       (plain-dispatch-argument? interface)
       (andmap (lambda (entry)
                 (same-policy-payload? (slot-read-value (car entry)) (cdr entry)))
               default-method-payloads)
       (default-function-method executor role interface)))
(def (reobserve-default-method! executor role interface)
  (def method #f)
  (with-catch
    (lambda (cause)
      ;; Once the native operation begins delivery, preserve the exact
      ;; observer failure. Only a pre-delivery refusal selects the Generic.
      (if method (raise cause) #f))
    (lambda ()
      (reobserve-slot-reads! default-method-reads
        (lambda ()
          ;; POO has authenticated the issued traversal and owns its replay
          ;; window. Check the mutable policy payload before its first read
          ;; is delivered. Keep all original deliveries and its return check.
          (unless method
            (set! method (current-default-method executor role interface))
            (unless method (raise 'unsupported-default-authoring-method)))))
      method)))
(def (plain-method-trace? reads)
  (andmap (lambda (read) (plain-dispatch-argument? (slot-read-receiver read))) reads))
(def (observe-default-method! executor role interface (source? #f))
  (def (deliver!) (reobserve-default-method! executor role interface))
  (def (reuse! trace)
    (def selected #f)
    (with-catch
      (lambda (cause)
        ;; A pre-selection miss can still take ordinary dispatch. After
        ;; selection, preserve the protected return's original refusal.
        (if selected (raise cause) #f))
      (lambda ()
        (call-with-current-slot-reads default-method-reads
          (lambda (_visits)
            (when (andmap plain-dispatch-argument? (cdr trace))
              (set! selected (current-default-method executor role interface)))))))
    ;; Forward only after native return authentication. The real method,
    ;; role reads and result Type all run in the original caller scope.
    (when selected (%record-slot-reads! (car trace)))
    selected)
  (or (and source? default-method-trace (object-construction-current?)
           (reuse! default-method-trace))
      (let ()
        (defvalues (method reads)
          (with-catch
            (lambda (cause) (deliver!) (raise cause))
            (lambda ()
              (without-observation
                (lambda () (%call-with-recorded-slot-reads deliver!))))))
        (cond
         ((not method) #f)
         ((plain-method-trace? reads)
          (%record-slot-reads! reads)
          method)
         (else (deliver!))))))
(def current-authoring-carrier-demand (make-parameter #f))
(def (authoring-generic-call executor role interface datum)
  ;; Only this actual Generic branch requests carrier support. Nested calls
  ;; share the first guard and its return check in the enclosing dynamic scope.
  ((current-authoring-carrier-demand))
  (module-authoring-analyze executor role interface datum))
(def (authoring-call executor role interface datum (source? #f))
  (cond
   ((and (owned-read-function-scope?)
         (andmap plain-dispatch-argument? (list executor role interface))
         ;; Universal logical-class dispatch on object data may run a getter.
         ;; Source datums are inert pairs/scalars; object data stays Generic.
         (not (object? datum))
         (observe-default-method! executor role interface source?))
    => (lambda (method) (invoke-function-method method interface role datum)))
   (else (authoring-generic-call executor role interface datum))))

(def (call-with-module-authoring-read-scope action)
  (if (current-authoring-carrier-demand) (action)
    (let (guard #f)
      (def (demand!)
        (unless guard (set! guard (clos-call-carrier-policy-guard)))
        (guard))
      (parameterize ((current-authoring-carrier-demand demand!))
        (call-with-owned-read-projection authoring-closed-bodies
          (lambda () (when guard (guard))) action)))))

;; : (-> PooModuleInterface Symbol PooModuleSourceRole)
(def (yuanxu-module-authoring-role interface role-name)
  (unless (yuanxu-module-interface? interface)
    (error "module authoring admission requires a POO Module Interface"
           interface))
  (let (authoring (yuanxu-module-interface-authoring interface))
    (unless (.slot? authoring role-name)
      (error "module authoring Profile does not define the requested source role"
             role-name))
    (.ref authoring role-name)))

;; Resolve the actual arguments once. A contributed method may rebind the
;; Profile; admission must describe the role dispatched for THIS datum.
(def (with-authoring-analysis interface role-name datum consume
                              (source? #f) (stock-method #f))
  (let* ((authoring (yuanxu-module-interface-authoring interface))
         (executor (.ref authoring 'executor))
         (role (yuanxu-module-authoring-role interface role-name)))
    (call-with-module-authoring-read-scope
      (lambda ()
        (consume role
          (validate-authoring-diagnostics
            (if stock-method
              (begin
                (%record-slot-reads! (car default-method-trace))
                (invoke-function-method stock-method interface role datum))
              (authoring-call executor role interface datum source?))))))))

;; One typed functional result per datum, through the SAME extensible Generic.
(def (yuanxu-module-authoring-analyze-datum interface role-name datum)
  (with-authoring-analysis interface role-name datum
    (lambda (_role diagnostics) diagnostics)))

;; : (-> PooModuleInterface Symbol SchemeDatum PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admit-datum interface role-name datum)
  (with-authoring-analysis interface role-name datum
    (cut yuanxu-module-authoring-admission interface <> <>)))

(def (authoring-datum-diagnostics interface role-name datums (source? #f))
  (foldr append '()
         (map (lambda (datum)
                (with-authoring-analysis interface role-name datum
                  (lambda (_role diagnostics) diagnostics) source?))
              datums)))

(def (stock-role-diagnostics interface role-name datums)
  (def (individual) (authoring-datum-diagnostics interface role-name datums #t))
  ;; Only a warm Interface and a maintained role can reach the protected
  ;; path. A changed result Type may execute author code on the first row.
  (if (not (and (pair? datums) (pair? (cdr datums))
                default-method-trace (not (current-module-source-observer))
                (owned-read-function-scope?) (object-construction-current?)
                (stock-role-policy-current?) (plain-dispatch-argument? interface)
                (not (ormap object? datums))))
    (individual)
    (let* ((profile (without-observation (lambda () (.ref/cached interface 'authoring))))
           (role (and (plain-dispatch-argument? profile)
                      (without-observation (lambda () (.ref/cached profile role-name)))))
           (executor (and role (without-observation (lambda () (.ref/cached profile 'executor))))))
      (def method
        (and (memq role stock-source-roles)
             (without-observation
               (lambda ()
                 (and (eq? (.ref/cached interface 'module-interface?) #t)
                      (string? (.ref/cached interface 'id)))))
             (andmap plain-dispatch-argument? (cdr default-method-trace))
             (current-default-method executor role interface)))
      (if (not method) (individual)
        (let ((entered? #f) (result #f) (delivered '()) (failed? #f) (failure #f))
          (def (run!)
            (unless entered?
              (set! entered? #t)
              (let-values (((value reads)
                            (%call-with-recorded-slot-reads
                              (lambda ()
                                (with-catch
                                  (lambda (cause) (set! failed? #t) (set! failure cause) #f)
                                  (lambda ()
                                    (foldr append '()
                                      (map-in-order
                                        (lambda (datum)
                                          ;; Keep every original read occurrence in
                                          ;; its datum's position in the outer trace.
                                          (with-authoring-analysis interface role-name datum
                                            (lambda (_role diagnostics) diagnostics)
                                            #t
                                            method))
                                        datums))))))))
                (set! result value)
                (set! delivered reads))))
          (def completed?
            (with-catch
              (lambda (cause)
                (if entered? (begin (%record-slot-reads! delivered)
                                     (if failed? (raise failure) (raise cause))) #f))
              (lambda ()
                (module-source-measure-operation 'source-authoring-role-checkpoint
                  (lambda ()
                    ;; Native re-observation retains the caller's read scope and
                    ;; owns both read sweeps. Isolate its checkpoint deliveries.
                    (%call-with-recorded-slot-reads
                      (lambda () (reobserve-slot-reads! default-method-reads run!)))
                    #t)))))
          (if completed?
            (begin (%record-slot-reads! delivered)
                   (if failed? (raise failure) result))
            (individual)))))))

;; : (-> PooModuleInterface Symbol [SchemeDatum] PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admit-datums interface role-name datums)
  ;; Consume the caller's inert source snapshot. Dispatch and validation still
  ;; run for every datum; only the final POO admission receipt is constructed.
  ;; Neither method selection nor acceptance is cached.
  (yuanxu-module-authoring-admission
   interface
   (yuanxu-module-authoring-role interface role-name)
   (authoring-datum-diagnostics interface role-name datums)))

(def (stock-empty-authoring-receipt? interface role)
  ;; Revision zero is the native construction generation. A replaced or
  ;; restored Type/prototype must run the actual receipt validator again.
  (and (owned-read-function-scope?)
       (object-construction-current?)
       (zero? (object-revision Type.))
       (zero? (object-revision YuanxuModuleAuthoringAdmission))
       (zero? (object-revision ModuleAuthoringAdmission))
       (plain-dispatch-argument? interface)
       (plain-dispatch-argument? role)
       (object-%instance interface)
       (object-%instance role)
       ;; Do not run a new owner callback while deciding whether to use the
       ;; stock result. Source/role validation already demanded these fields.
       (without-observation
         (lambda ()
           (and (string? (.ref/cached interface 'id (lambda () #f)))
                (symbol? (.ref/cached role 'identity (lambda () #f))))))
       ;; Retain native dependencies on the actual Type methods, the stock
       ;; prototype and the owner fields across later publication effects.
       (procedure? (.ref YuanxuModuleAuthoringAdmission '.validate))
       (eq? (.ref YuanxuModuleAuthoringAdmission '.element?) yuanxu-module-authoring-admission-shape?)
       (.all-slots ModuleAuthoringAdmission)
       (string? (yuanxu-module-interface-id interface))
       (symbol? (.ref role 'identity))))

(def (yuanxu-module-authoring-source-admit interface role-name datums)
  (def role (yuanxu-module-authoring-role interface role-name))
  (def diagnostics (stock-role-diagnostics interface role-name datums))
  ;; Source admission consumes only a refusal diagnostic. All datum and
  ;; diagnostic Type work has completed before the stock receipt decision.
  (if (and (null? diagnostics) (stock-empty-authoring-receipt? interface role))
    (values #t #f)
    (let (receipt (yuanxu-module-authoring-admission interface role diagnostics))
      (if (yuanxu-module-authoring-admission-accepted? receipt)
        (values #t #f)
        (values #f (car (yuanxu-module-authoring-admission-diagnostics receipt)))))))

;; The public port API keeps its original streaming reader semantics.
;; : (-> PooModuleInterface Symbol InputPort PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admit-port interface role-name port)
  (yuanxu-module-authoring-admission
   interface
   (yuanxu-module-authoring-role interface role-name)
   (yuanxu-read-datums/append-map
    (cut yuanxu-module-authoring-analyze-datum interface role-name <>)
    port)))

(def (yuanxu-module-authoring-admission? value)
  (element? YuanxuModuleAuthoringAdmission value))

(def (yuanxu-module-authoring-admission-accepted? admission)
  (.ref admission 'accepted?))

(def (yuanxu-module-authoring-admission-diagnostics admission)
  (.ref admission 'diagnostics))
