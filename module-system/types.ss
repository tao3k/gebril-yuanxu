;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: native Module System types and authoring role contracts.
(import (only-in :clan/poo/object .o .cc object?)
        (only-in :clan/poo/mop define-type Object Bool)
        (only-in :clan/poo/type Symbol List)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :clan/poo/object-contract-validation validation-fields)
        (only-in :clan/poo/validation-rebinding rebind-validation)
        (only-in :yuanxu/object-family/read-projection owned-read-derived!)
        (only-in :yuanxu/object-types/contracts
                 YuanxuContract. YuanxuObjectContract.
                 yuanxu-classification-evidence)
        (only-in :yuanxu/module-system/schema/relations
                 SemanticImports.
                 ModuleIdentityContract ModuleImportsContract
                 ModuleProfilesContract ModuleCapabilitiesContract))
(export ModuleSourceRoleContract ModuleAuthoringProfileContract
        SemanticModuleContract)

;; : (-> Unit POOObject)
(def (semantic-empty-prototype) (.o))

;; : (-> Object Object YuanxuClassificationEvidence)
(def (semantic-object-classify candidate context)
  (yuanxu-classification-evidence
   'semantic-object candidate (object? candidate)
   (if (object? candidate) '() '(expected-poo-object)) context))

;;; Boundary: executor strategy is any native POO value. Concrete method
;;; bundles still specialize its prototype identity through CLOS.
(define-type (SemanticObject @ YuanxuContract.)
  identity: 'semantic-object
  .classify: semantic-object-classify)

;; Value shape is a public library check, not a contextual admission per scalar.
;; Preserve the existing open extension envelope: additional role policy fields
;; are allowed, while all declared fields still have to satisfy their Types.
(def RoleSymbols (List Symbol))
;; The public library creates and supplies this exact fresh checked receiver.
;; Only add lifetime enrollment; its validators, result identity, normalization,
;; shape checks and final obligations remain the original public protocol.
(def (prepare-role-validation fields)
  (let (checks
        (map (lambda (entry)
               (cons (car entry)
                 (lambda (original checked)
                   (owned-read-derived! checked)
                   ((cdr entry) original checked))))
             (validation-fields fields)))
    (lambda (candidate) (rebind-validation candidate checks))))
(define-type (ModuleSourceRoleValueContract @ ObjectContract. prepared-responsibilities)
  identity: 'module-source-role-value
  extra-fields: 'delegate
  constraints: (list Object)
  prepared-validation: (prepare-role-validation prepared-responsibilities)
  responsibilities:
  (.o identity: Symbol
      recommended-forms: RoleSymbols
      forbidden-slot-verbs: RoleSymbols
      forbidden-root-forms: RoleSymbols
      recursive-root-forms?: Bool
      forbidden-imports: RoleSymbols
      forbidden-forms: RoleSymbols
      forbid-raw-behavior-hooks?: Bool
      forbid-raw-query-initializers?: Bool
      repair-operators: RoleSymbols
      freedom: Symbol))

;;; A source role is an extensible policy value, not a hard-coded linter mode.
;;; The lists describe recommended syntax and repair vocabulary; they are not
;;; a closed grammar.  Execution remains owned by the authoring Contract
;;; executor, and refined roles may add contextual prohibitions.
(define-type (ModuleSourceRoleContract @ YuanxuObjectContract.)
  identity: 'module-source-role
  proto: (semantic-empty-prototype)
  value-contract:
  (.cc ModuleSourceRoleValueContract 'required-prototype proto))

;;; Every semantic Module carries one role-indexed authoring Profile.  A
;;; vertical module may refine individual role objects without replacing the
;;; admission protocol or disabling unrelated rules.
(define-type (ModuleAuthoringProfileContract @ YuanxuObjectContract.)
  identity: 'module-authoring-profile
  proto: (semantic-empty-prototype)
  responsibilities:
  (.o executor: SemanticObject
      types: ModuleSourceRoleContract
      objects: ModuleSourceRoleContract
      funs: ModuleSourceRoleContract
      config: ModuleSourceRoleContract
      interface: ModuleSourceRoleContract))

;;; Invariant: a semantic module is admitted only through every native
;;; responsibility, including its role-indexed authoring Profile.
(define-type (SemanticModuleContract @ YuanxuObjectContract.)
  identity: 'semantic-module
  proto: (.o imports: SemanticImports.)
  responsibilities:
  (.o identity: ModuleIdentityContract
      imports: ModuleImportsContract
      capabilities: ModuleCapabilitiesContract
      profiles: ModuleProfilesContract
      authoring: ModuleAuthoringProfileContract))
