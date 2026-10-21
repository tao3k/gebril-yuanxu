;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: construct values from prototypes owned by explicit Type declarations.
(import (only-in :clan/poo/object .o .mix .ref)
        (only-in :clan/poo/mop validate)
        :yuanxu/module-system/schema/relations
        :yuanxu/module-system/types
        (only-in :yuanxu/module-system/objects
                 SemanticModule. ModuleSourceRole. ModuleAuthoringProfile.
                 make-semantic-module))
(export SemanticModule. ModuleSourceRole.
        ModuleAuthoringProfile. ModuleAuthoringExecutor.
        TypesSourceRole. ObjectsSourceRole. FunsSourceRole.
        ConfigSourceRole.
        InterfaceSourceRole. BuildSourceRole.
        SemanticModuleContract
        ModuleSourceRoleContract ModuleAuthoringProfileContract
        yuanxu-semantic-module
        make-default-module-authoring-profile
        yuanxu-default-module-authoring-profile)

;;; The executor stays a native POO prototype.  CLOS specializes it through
;;; the explicit prototype bridge rather than requiring a duplicate class.
(def ModuleAuthoringExecutor.
  (.o identity: 'module-authoring/default-executor))

;; : (-> Symbol [Symbol] [Symbol] [Symbol] Symbol PooModuleSourceRole)
(def (yuanxu-module-source-role identity-value recommended-forms-value
                                  forbidden-slot-verbs-value
                                  forbidden-root-forms-value freedom-value)
  (validate ModuleSourceRoleContract
    (.o (:: @ ModuleSourceRole.)
        identity: identity-value
        recommended-forms: recommended-forms-value
        forbidden-slot-verbs: forbidden-slot-verbs-value
        forbidden-root-forms: forbidden-root-forms-value
        recursive-root-forms?: #f
        forbidden-imports: '()
        forbidden-forms: '()
        forbid-raw-behavior-hooks?: #f
        forbid-raw-query-initializers?: #t
        repair-operators: '(? => =>.+ override)
        freedom: freedom-value)))

;;; Role Profiles state the default engineering envelope.  They intentionally
;;; admit ordinary Scheme helpers; the Contract rejects only competing public
;;; semantics, leaving algorithms and domain behavior open to the module owner.
(def TypesSourceRole.
  (yuanxu-module-source-role
   'types '(define-type def defstruct) '(add remove replace delete) '()
   'open-with-boundary-contracts))
(def ObjectsSourceRole.
  (yuanxu-module-source-role
   'objects '(.def .o .defgeneric defmethod) '(add remove replace delete) '()
   'open-native-poo))
(def FunsSourceRole.
  (yuanxu-module-source-role
   'funs '(def lambda) '(add remove replace delete) '()
   'open-pure-functions))
(def ConfigSourceRole.
  (yuanxu-module-source-role
   'config '(.def .o user-composition use-module)
   '(add remove replace delete)
   '(stage graph loop prove handoff provider runtime)
   'composition-only))

(def InterfaceSourceRole.
  (yuanxu-module-source-role
   'interface '(import export .def .o) '(add remove replace delete) '()
   'module-assembly))

(def BuildSourceRole.
  (yuanxu-module-source-role
   'build '(import def .def .o) '(add remove replace delete) '()
   'build-publication-only))

(def (make-default-module-authoring-profile)
  ;; Internal construction stage. Source-policy getters must not capture the
  ;; temporary validation receipts of every child as enduring dependencies.
  ;; Each invocation still owns a fresh Profile and executor. The Interface
  ;; constructor validates this value before any role admission or expansion.
  (.o (:: @ ModuleAuthoringProfile.)
        executor: (.mix ModuleAuthoringExecutor.)
        types: TypesSourceRole.
        objects: ObjectsSourceRole.
        funs: FunsSourceRole.
        config: ConfigSourceRole.
        interface: InterfaceSourceRole.
        build: BuildSourceRole.))

(def (yuanxu-default-module-authoring-profile)
  ;; Public constructor retains immediate validation and checked-value identity.
  (validate ModuleAuthoringProfileContract
    (make-default-module-authoring-profile)))

;; : (-> ModuleIdentity imports: ModuleImports capabilities: ModuleCapabilities profiles: ModuleProfiles authoring: ModuleAuthoringProfile SemanticModule)
(def (yuanxu-semantic-module identity-value
                             imports: (imports-value (yuanxu-empty-imports))
                             capabilities: (capabilities-value (yuanxu-empty-capabilities))
                             profiles: (profiles-value (yuanxu-empty-profiles))
                             authoring: (authoring-value
                                         (yuanxu-default-module-authoring-profile)))
  (make-semantic-module identity-value authoring-value
                        imports: imports-value
                        capabilities: capabilities-value
                        profiles: profiles-value))
