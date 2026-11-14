;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source capabilities supply generation-qualified declarations, never user syntax.
(import (only-in :std/list/list delete-duplicates/hash)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/read-projection owned-read-function-scope?)
        (only-in :clan/poo/mop Type Type. Object define-type element?)
        (only-in :clan/poo/type Record Symbol List Or)
        (only-in :tao3k/yuanxu/types/contracts yuanxu-value-admit yuanxu-validation-evidence-accepted?)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-measure-operation))
(export ModulePublicationContract ModuleScopeContextContract ContributionRouteContract
        ModuleFeatureRefinementContract admit-module-value!
        module-publication? module-scope-context? module-publication-contract-current?)
;; Value admission is shared by interpreted and compiled consumers. It does
;; not acquire the authoring, filesystem or compiler capability of admission.ss.
(def (admit-module-value! contract candidate context-value)
  (let (evidence
        (module-source-measure-operation 'reader-value-admission
          (cut yuanxu-value-admit contract candidate context-value)))
    (unless (module-source-measure-operation 'reader-admission-evidence
              (cut yuanxu-validation-evidence-accepted? evidence))
      (error "module scope admission refused" (.ref contract 'identity) evidence))
    evidence))

(def (has-slots? value names)
  (and (object? value) (andmap (cut .slot? value <>) names)))
(define-type (Callable @ Type.) .element?: procedure?)
(def ScopeTypeShape
  (Record identity: [Symbol] .element?: [Callable] .validate: [Callable]))
(define-type (ScopeType @ Type.)
  .element?: (lambda (value)
               (and (object? value)
                    (module-source-measure-operation 'scope-shape-type
                      (cut element? Type value))
                    (module-source-measure-operation 'scope-shape-record
                      (cut element? ScopeTypeShape value))
                    (module-source-measure-operation 'scope-shape-protocol
                      (lambda () (not (ormap (cut .slot? value <>) '(.classify .obligations .admit))))))))
(define-type ModuleFeatureRefinementContract
  (.cc (Record refine: [Callable optional: #t] contract: [ScopeType optional: #t])
       identity: 'module/feature-refinement))
(define-type (ExportPath @ Type.)
  .element?: (lambda (path) (and (pair? path) (element? (List Symbol) path))))
(define-type ContributionRouteContract
  (.cc (Record target-owner: [Symbol] target-admission: [Symbol] export-path: [ExportPath])
       identity: 'module/contribution-route))
(def AdmissionRoute (Record export-path: [ExportPath] contract-path: [ExportPath]))
(def ((named-values? descriptor) value)
  (and (object? value)
       (andmap (lambda (name) (and (symbol? name) (element? descriptor (.ref value name))))
               (.all-slots value))))
(define-type (ContributionRoutes @ Type.) .element?: (named-values? ContributionRouteContract))
(define-type (AdmissionRoutes @ Type.) .element?: (named-values? AdmissionRoute))
(def PublicationShape
  (Record identity: [Symbol] features: [(Or Object (List Symbol))]
          core: [(Record contributions: [ContributionRoutes optional: #t]
                         admissions: [AdmissionRoutes optional: #t]
                         scope-contract: [ScopeType])]))
(def (module-publication? value)
  (and (module-source-measure-operation 'publication-shape-record
         (cut element? PublicationShape value))
       (module-source-measure-operation 'publication-shape-core
         (lambda ()
           (let (core (.ref value 'core))
             (and (.slot? core 'exports) (not (.slot? core 'requires)) (not (.slot? core 'link))))))))
(define-type (ModulePublicationContract @ Type.)
  identity: 'module/publication .element?: module-publication?)
;; Capture at definition, before contributors can extend the descriptor. A
;; restored method/value Contract is still another runtime revision and falls
;; back to guarded public reads. This is not a contributor-supplied pure flag.
(def publication-contract-revision (object-revision ModulePublicationContract))
(def (module-publication-contract-current?)
  (= publication-contract-revision (object-revision ModulePublicationContract)))
(def (symbol-set? value)
  (and (list? value) (andmap symbol? value)
       (= (length value) (length (delete-duplicates/hash value from-end?: #t)))))
(def (module-scope-context? value)
  (and (has-slots? value '(generation module-ids selected denied-modules
                          locate read-publication current?))
       (let (generation (.ref value 'generation))
         (and (string? generation) (> (string-length generation) 0)))
       (andmap (lambda (slot) (symbol-set? (.ref value slot)))
               '(module-ids selected denied-modules))
       (andmap (lambda (slot) (procedure? (.ref value slot)))
               '(locate read-publication current?))
       (andmap (lambda (slot) (or (not (.slot? value slot))
                                  (procedure? (.ref value slot))))
               '(eligible? namespace publication-preparation))
       (if (and (owned-read-function-scope?)
                (object-%precedence-list value) (not (object-protocol value))
                (object-%instance value)
                (hash-key? (object-%instance value) 'module-ids)
                (hash-key? (object-%instance value) 'selected))
         ;; These fields were actually validated above and remain warm. Native
         ;; reads below still issue/deliver their original dependency records.
         ;; The known observer/precheck route cannot call a user hook on this
         ;; warm protocol-free receiver. Build only an invocation-local symbol
         ;; identity index; do not retain it or a successful Type decision.
         (let (selected (.ref value 'selected))
           (or (null? selected)
               (let ((ids (.ref value 'module-ids)) (index (make-hash-table-eq)))
                 (for-each (lambda (id) (hash-put! index id #t)) ids)
                 (andmap (cut hash-key? index <>) selected))))
         ;; Open observers/prechecks, protocols and cold values preserve the
         ;; existing per-element read/delivery/effect order without snapshots.
         (andmap (lambda (id) (memq id (.ref value 'module-ids)))
                 (.ref value 'selected))) #t))
(define-type (ModuleScopeContextContract @ Type.)
  identity: 'module/scope-context .element?: module-scope-context?)
