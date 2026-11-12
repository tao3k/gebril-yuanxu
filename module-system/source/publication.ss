;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source capabilities supply generation-qualified declarations, never user syntax.
(import (only-in :std/list/list delete-duplicates/hash)
        (prefix-in (only-in :gerbil/runtime/mop class-of slot-ref) runtime.)
        (only-in :gerbil/runtime/error Error::t)
        (runtime: :clan/poo/object)
        (only-in :tao3k/yuanxu/object-family/read-projection owned-read-function-scope?)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :clan/poo/slot-observation slot-read-revision slot-read-instance slot-read-value)
        (only-in :clan/poo/mop Type Type. Bool Object define-type element?)
        (only-in :clan/poo/type Record Symbol List Or)
        (only-in :tao3k/yuanxu/object-types/contracts yuanxu-value-admit yuanxu-validation-evidence-accepted?)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-measure-operation))
(export ModulePublicationContract ModuleScopeContextContract ContributionRouteContract ModuleInterfaceViewContract
        ModuleFeatureRefinementContract admit-module-value!
        module-publication? module-scope-context? requirement-option
        module-publication-contract-current? module-publication-dependency-projection
        module-publication-recorded-dependencies)
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
                    (element? Type value)
                    (element? ScopeTypeShape value)
                    (not (ormap (cut .slot? value <>) '(.classify .obligations .admit))))))
(define-type (InterfaceView @ Type.) .element?: (cut eq? <> 'interface))
(def RequirementShape
  (Record module-id: [Symbol]
          contract: [ScopeType optional: #t]
          refine: [Callable optional: #t]
          publish?: [Bool optional: #t]
          view: [InterfaceView optional: #t]))
(define-type ModuleFeatureRefinementContract
  (.cc (Record refine: [Callable optional: #t] contract: [ScopeType optional: #t])
       identity: 'module/feature-refinement))
(def (requirement-option requirement key)
  (and (.slot? requirement key) (.ref requirement key)))
(define-type (Requirement @ Type.)
  .element?: (lambda (value)
               (and (element? RequirementShape value)
                    (not (.has? value view refine)))))
(define-type ModuleInterfaceViewContract
  (.cc (Record identity: [Symbol] requires: [Object]) identity: 'module/interface-view))
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
(define-type (Requirements @ Type.) .element?: (named-values? Requirement))
(define-type (ContributionRoutes @ Type.) .element?: (named-values? ContributionRouteContract))
(define-type (AdmissionRoutes @ Type.) .element?: (named-values? AdmissionRoute))
(def PublicationShape
  (Record identity: [Symbol] features: [(Or Object (List Symbol))]
          core: [(Record contributions: [ContributionRoutes optional: #t]
                         admissions: [AdmissionRoutes optional: #t]
                         requires: [Requirements] scope-contract: [ScopeType] link: [Callable])]))
(def (module-publication? value) (element? PublicationShape value))
(define-type (ModulePublicationContract @ Type.)
  identity: 'module/publication .element?: module-publication?)
;; Capture at definition, before contributors can extend the descriptor. A
;; restored method/value Contract is still another runtime revision and falls
;; back to guarded public reads. This is not a contributor-supplied pure flag.
(def publication-contract-revision (object-revision ModulePublicationContract))
(def (module-publication-contract-current?)
  (= publication-contract-revision (object-revision ModulePublicationContract)))
;; Runtime names records own a separate spine. Compare only finite symbolic
;; sequences; malformed/cyclic snapshots fall back without invoking a getter.
;; Ordinary cached values still require identity, not structural equivalence.
(def (same-slot-names? left right)
  (and (list? left) (list? right)
    (let loop ((left left) (right right))
      (cond ((null? left) (null? right))
            ((null? right) #f)
            (else (and (symbol? (car left)) (eq? (car left) (car right))
                       (loop (cdr left) (cdr right))))))))
(def (module-publication-dependency-projection value observed?)
  ;; Even hash-get dispatches through mutable Gerbil table metadata. Qualify
  ;; both native routes before using either cache. A changed route abandons
  ;; this shortcut; the caller's full currentness path owns the refusal.
  (def (route-current? key reads instance)
    (with-catch
      ;; The native route guard raises plain Errors. A watchdog or another
      ;; condition must still unwind the publication instead of falling back.
      (lambda (failure)
        (if (eq? (runtime.class-of failure) Error::t) #f (raise failure)))
      (lambda () (require-read-route! key reads instance) #t)))
  (def (cached receiver key)
    (and (object? receiver) (object-%precedence-list receiver)
         (not (object-protocol receiver))
         (let ((instance (object-%instance receiver)) (reads (object-%reads receiver)))
           (and instance reads (route-current? key reads instance)
                (let* ((names? (equal? key '(names)))
                       (value (if names? (object-%all-slots receiver) (hash-get instance key)))
                       (read (hash-get reads key)))
                  (and read (observed? read)
                       (= (slot-read-revision read) (object-revision receiver))
                       (eq? (slot-read-instance read) instance)
                       (if names?
                         ;; Check the native snapshot before any defensive list
                         ;; copy; a malformed spine must not enter list-copy.
                         (same-slot-names? (runtime.slot-ref read 'value) value)
                         (eq? (slot-read-value read) value))
                       value))))))
  (and (module-publication-contract-current?)
       (let* ((core (cached value 'core))
              (requires (cached core 'requires))
              (names (cached requires '(names))))
         (and names
              (let ((complete? #t))
                (let (ids
                       (map (lambda (name)
                              (let* ((requirement (cached requires name))
                                     (id (cached requirement 'module-id)))
                                (unless (symbol? id) (set! complete? #f))
                                id)) names))
                  (and complete? ids)))))))
(def (module-publication-recorded-dependencies value roots)
  ;; An empty requires object needs only core, requires and its names token.
  ;; Check those directly in the original capture. A dependency edge can
  ;; demand more tokens, so retain the original eq? index for wider projections.
  (def remaining 3)
  (def index #f)
  (module-publication-dependency-projection value
    (lambda (read)
      (if (positive? remaining)
        (begin (set! remaining (1- remaining)) (memq read roots))
        (begin
          (unless index
            (set! index (make-hash-table-eq))
            (for-each (lambda (root) (hash-put! index root #t)) roots))
          (hash-key? index read))))))
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
