;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: shared role-aware source admission for one loaded Module Interface.
;;; Invariant: source is read as inert data; this owner never expands or runs it.

(import (only-in :clan/poo/object .def .o .ref .slot? object?)
        (only-in :clan/poo/mop Type. define-type element? validate)
        (only-in :std/list/list any filter-map find)
        (only-in :yuanxu/utilities/algorithms
                 yuanxu-read-datums/append-map
                 yuanxu-scheme-datum-find)
        (only-in :yuanxu/module-system/source/interface
                 yuanxu-module-interface-prototype
                 yuanxu-module-interface?
                 yuanxu-module-interface-id
                 yuanxu-module-interface-authoring)
        (only-in :yuanxu/module-system/observability/presentation
                 yuanxu-poo-slot-authoring-datum-bindings
                 yuanxu-poo-slot-authoring-self-reference?)
        ;; Role admission needs dispatch and immutable method declarations, not
        ;; the aggregate class evolution/reflection/load-form publication.
        (only-in :yuanxu/poo-clos/objects
                 poo-clos-generic-protocol
                 poo-clos-generic-binding-current poo-clos-compose-method-bundle
                 clos-call-carrier-policy-guard)
        (only-in :yuanxu/object-family/read-projection call-with-owned-read-projection)
        (only-in :yuanxu/poo-clos/generic-syntax .defgeneric .defmethod)
        (only-in :yuanxu/poo-clos/dispatch poo-clos-call)
        (only-in :yuanxu/poo-clos/method-bundle-syntax .defmethod-bundle)
        (only-in :yuanxu/module-system/authoring/roles ModuleAuthoringExecutor. ModuleSourceRole. ConfigSourceRole.))

(export ModuleAuthoringAdmissionProtocol
        ModuleAuthoringAdmissionGeneric
        ModuleAuthoringCoreMethods
        YuanxuModuleAuthoringDiagnostic
        YuanxuModuleAuthoringAdmission
        yuanxu-module-authoring-role
        yuanxu-module-authoring-admit-datum
        yuanxu-module-authoring-admit-datums
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

(def (yuanxu-module-authoring-admission-shape? value)
  (and (object? value)
       (andmap (cut .slot? value <>)
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
        rule: 'native-poo-slot-algebra-only
        recommendation: 'rename-as-domain-noun-and-refine-native-slot
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
;;; reads only the native Scheme import datum; it does not expand or evaluate
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
             'poo-query-must-be-native-object
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
  (validate YuanxuModuleAuthoringAdmission
    (.o (:: @ ModuleAuthoringAdmission)
        module: (yuanxu-module-interface-id interface)
        role: (.ref source-role 'identity)
        accepted?: (null? diagnostic-values)
        diagnostics: diagnostic-values)))

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

(def (yuanxu-module-authoring-admit/common interface role datum)
  (yuanxu-module-authoring-admission interface role
    (yuanxu-module-authoring-diagnostics/common interface role datum)))

(def (yuanxu-module-authoring-admit/config interface role datum)
  (yuanxu-module-authoring-admission interface role
    (yuanxu-module-authoring-diagnostics/config interface role datum)))

;;; Executor strategy and SourceRole are independently extensible. Module
;;; packages can contribute a method bundle for a refined executor/role pair
;;; without extending a central role switch.
(def ModuleAuthoringAdmissionProtocol
  (poo-clos-generic-protocol 'module-system/authoring-admission))

(.defgeneric module-authoring-admit (executor role interface datum)
  (protocol ModuleAuthoringAdmissionProtocol))

;; Keep the exported generic object: contributor bundles compose with this
;; exact protocol owner, rather than a separately constructed lookalike.
(def ModuleAuthoringAdmissionGeneric
  (poo-clos-generic-binding-current module-authoring-admit$poo-clos-generic))

;; One source-level rule owns the shared crossing; normal .defmethod lowering
;; supplies the specializers, lexical frame and lambda-list contract.
(defrules authoring-method ()
  ((_ role-prototype admit)
   (.defmethod (module-authoring-admit
                 (executor (prototype ModuleAuthoringExecutor.))
                 (role (prototype role-prototype))
                 (interface (prototype yuanxu-module-interface-prototype))
                 datum)
     (admit interface role datum))))

(.defmethod-bundle ModuleAuthoringCoreMethods
  ModuleAuthoringAdmissionProtocol
  (authoring-method ModuleSourceRole. yuanxu-module-authoring-admit/common)
  (authoring-method ConfigSourceRole. yuanxu-module-authoring-admit/config))

(poo-clos-compose-method-bundle
 ModuleAuthoringAdmissionGeneric
 ModuleAuthoringCoreMethods)

;; The generated wrappers retain the normal public dispatch boundary. Batch
;; admission must also construct and validate each invocation: native observers
;; may inspect carrier policy reads or contribute effects at those reads.
(def authoring-closed-bodies
  (map (cut .ref <> 'body) (.ref ModuleAuthoringCoreMethods 'methods)))

(def (call-with-module-authoring-read-scope action)
  (call-with-owned-read-projection authoring-closed-bodies
    (clos-call-carrier-policy-guard) action))

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

;; : (-> PooModuleInterface Symbol SchemeDatum PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admit-datum interface role-name datum)
  (let* ((authoring (yuanxu-module-interface-authoring interface))
         (executor (.ref authoring 'executor))
         (role (yuanxu-module-authoring-role interface role-name)))
    (call-with-module-authoring-read-scope
      (cut poo-clos-call ModuleAuthoringAdmissionGeneric
           executor role interface datum))))

;; : (-> PooModuleInterface Symbol [SchemeDatum] PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admit-datums interface role-name datums)
  ;; Consume the caller's inert source snapshot. Dispatch and validation still
  ;; run for every datum; neither method selection nor acceptance is cached.
  (yuanxu-module-authoring-admission
   interface
   (yuanxu-module-authoring-role interface role-name)
   (foldr append '()
          (map (lambda (datum)
            (.ref (yuanxu-module-authoring-admit-datum interface role-name datum)
                  'diagnostics))
          datums))))

;; The public port API keeps its original streaming reader semantics.
;; : (-> PooModuleInterface Symbol InputPort PooModuleAuthoringAdmission)
(def (yuanxu-module-authoring-admit-port interface role-name port)
  (yuanxu-module-authoring-admission
   interface
   (yuanxu-module-authoring-role interface role-name)
   (yuanxu-read-datums/append-map
    (lambda (datum)
      (.ref (yuanxu-module-authoring-admit-datum
             interface role-name datum)
            'diagnostics))
    port)))

(def (yuanxu-module-authoring-admission? value)
  (element? YuanxuModuleAuthoringAdmission value))

(def (yuanxu-module-authoring-admission-accepted? admission)
  (.ref admission 'accepted?))

(def (yuanxu-module-authoring-admission-diagnostics admission)
  (.ref admission 'diagnostics))
