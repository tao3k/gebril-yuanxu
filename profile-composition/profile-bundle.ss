;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: POO-native Module profile selection and pure ProfileBundle algebra.
;;; Invariant: selection indexes are built once by the Module owner; composition
;;; neither discovers packages nor executes Runtime behavior.

(import (only-in :clan/poo/object .all-slots .mix .o .ref .slot? object?)
        (only-in :clan/poo/mop Type. define-type element? validate)
        (only-in :std/error deferror-class)
        (only-in :std/list/list append-map delete-duplicates/hash every filter-map)
        (only-in :yuanxu/module-system/types
                 SemanticModuleContract)
        (only-in :yuanxu/module-system/schema/relations yuanxu-empty-profiles)
        (only-in :yuanxu/profile-composition/bindings
                 yuanxu-scenario-module-binding
                 yuanxu-scenario-profile-binding))

(export +yuanxu-profile-export-kind+
        +yuanxu-profile-selection-proof-kind+
        +yuanxu-profile-bundle-kind+
        +yuanxu-profile-composition-strategy-kind+
        YuanxuProfileExport
        YuanxuProfileSelectionProof
        YuanxuProfileBundle
        YuanxuStageSpace
        YuanxuProfileCompositionStrategy
        profiles
        compose
        yuanxu-profile-export
        yuanxu-module-profiles
        yuanxu-select-module-profiles
        yuanxu-profile-bundle
        yuanxu-profile-bundle?
        YuanxuProfileCompositionConflict?
        YuanxuProfileCompositionConflict-receipt
        yuanxu-profile-composition-conflict-presentation)

(deferror-class YuanxuProfileCompositionConflict (receipt))

;;; Provenance is a maintainer claim, never an inferred source location.
(def (yuanxu-profile-conflict-source value)
  (let (claim
        (if (element? YuanxuProfileSelectionProof value)
          (.ref (.ref value 'profile-export) 'provenance)
          (if (and (object? value) (.slot? value 'provenance))
            (.ref value 'provenance)
            #f)))
    (if (and (object? claim)
             (.slot? claim 'source-path)
             (.slot? claim 'source-line)
             (string? (.ref claim 'source-path))
             (> (string-length (.ref claim 'source-path)) 0)
             (integer? (.ref claim 'source-line))
             (> (.ref claim 'source-line) 0))
      (.o source-path: (.ref claim 'source-path)
          source-line: (.ref claim 'source-line)
          status: 'declared)
      (.o source-path: #f source-line: #f status: 'undeclared))))

(def (yuanxu-profile-conflict-source-label source)
  (if (eq? (.ref source 'status) 'declared)
    (string-append (.ref source 'source-path) ":"
                   (number->string (.ref source 'source-line)))
    "source undeclared"))

(def (yuanxu-profile-composition-conflict-presentation failure (level 'default))
  (unless (YuanxuProfileCompositionConflict? failure)
    (error "not a Profile composition conflict" failure))
  (unless (memq level '(default advanced))
    (error "unknown Profile conflict presentation level" level))
  (let* ((receipt (YuanxuProfileCompositionConflict-receipt failure))
         (ordinary
          (.o identity: (.ref receipt 'identity)
              reason: (.ref receipt 'reason)
              constraint: (.ref receipt 'constraint)
              previous-source: (.ref receipt 'previous-source)
              candidate-source: (.ref receipt 'candidate-source)
              repair: 'select-one-profile-or-align-its-revision)))
    (if (eq? level 'default)
      ordinary
      (.o (:: @ ordinary)
          previous-value: (.ref receipt 'previous-value)
          candidate-value: (.ref receipt 'candidate-value)))))

(def (yuanxu-raise-profile-composition-conflict
      identity-value reason-value constraint-value
      prior-profile candidate-profile)
  (let* ((previous-source-value
          (yuanxu-profile-conflict-source prior-profile))
         (candidate-source-value
          (yuanxu-profile-conflict-source candidate-profile))
         (receipt-value
          (.o identity: identity-value
              reason: reason-value
              constraint: constraint-value
              previous-source: previous-source-value
              candidate-source: candidate-source-value
              previous-value: prior-profile
              candidate-value: candidate-profile))
         (failure
          (YuanxuProfileCompositionConflict
           (string-append
            "Profile " (symbol->string identity-value) " conflicts on "
            (symbol->string reason-value) " ("
            (yuanxu-profile-conflict-source-label previous-source-value)
            " vs "
            (yuanxu-profile-conflict-source-label candidate-source-value)
            ")")
           irritants: '())))
    (set! (YuanxuProfileCompositionConflict-receipt failure) receipt-value)
    (raise failure)))

(def +yuanxu-profile-export-kind+ 'yuanxu.profile-export.v1)
(def +yuanxu-profile-selection-proof-kind+
  'yuanxu.profile-selection-proof.v1)
(def +yuanxu-profile-bundle-kind+ 'yuanxu.profile-bundle.v1)
(def +yuanxu-profile-composition-strategy-kind+
  'yuanxu.profile-composition-strategy.v1)

(def (yuanxu-object-shape? value kind slots)
  (and (object? value)
       (every (cut .slot? value <>) slots)
       (eq? (.ref value 'kind) kind)))

;;; A Stage space is the progressive-disclosure boundary: the space is always
;;; a POO object so named stages inherit and override natively, while each slot
;;; may remain an inert data value.  An object-valued slot opts into recursive
;;; POO extension.  Executable procedures are never Stage data.
(def (yuanxu-stage-value-shape? value)
  (or (object? value) (not (procedure? value))))

(def (yuanxu-stage-space-shape? value)
  (and (object? value)
       (every
        (lambda (stage-name)
          (and (symbol? stage-name)
               (yuanxu-stage-value-shape? (.ref value stage-name))))
        (.all-slots value))))

(define-type (YuanxuStageSpace @ Type.)
  .element?: yuanxu-stage-space-shape?)

(def (yuanxu-profile-export-shape? value)
  (and (yuanxu-object-shape?
        value
        +yuanxu-profile-export-kind+
        '(kind identity profile dependency-roots capability-requirements
               revision generation provenance runtime-executed?))
       (symbol? (.ref value 'identity))
       (object? (.ref value 'profile))
       (list? (.ref value 'dependency-roots))
       (list? (.ref value 'capability-requirements))
       (symbol? (.ref value 'revision))
       (symbol? (.ref value 'generation))
       (eq? (.ref value 'runtime-executed?) #f)))

(define-type (YuanxuProfileExport @ Type.)
  .element?: yuanxu-profile-export-shape?)

(def (yuanxu-profile-selection-proof-shape? value)
  (and (yuanxu-object-shape?
        value
        +yuanxu-profile-selection-proof-kind+
        '(kind module-definition module-instance profile-identity revision
               generation profile-export accepted? diagnostics
               runtime-executed?))
       (element? YuanxuProfileExport (.ref value 'profile-export))
       (symbol? (.ref value 'profile-identity))
       (eq? (.ref value 'accepted?) #t)
       (null? (.ref value 'diagnostics))
       (eq? (.ref value 'runtime-executed?) #f)))

(define-type (YuanxuProfileSelectionProof @ Type.)
  .element?: yuanxu-profile-selection-proof-shape?)

(def (yuanxu-profile-bundle-shape? value)
  (and (yuanxu-object-shape?
        value
        +yuanxu-profile-bundle-kind+
        '(kind module-bindings profiles profile-identities imports capabilities
               selection-proofs stages profile-bindings provenance
               runtime-executed?))
       (list? (.ref value 'module-bindings))
       (list? (.ref value 'profiles))
       (every object? (.ref value 'profiles))
       (list? (.ref value 'profile-identities))
       (every symbol? (.ref value 'profile-identities))
       (= (length (.ref value 'profiles))
          (length (.ref value 'profile-identities)))
       (list? (.ref value 'imports))
       (list? (.ref value 'capabilities))
       (list? (.ref value 'selection-proofs))
       (every (cut element? YuanxuProfileSelectionProof <>)
              (.ref value 'selection-proofs))
       (element? YuanxuStageSpace (.ref value 'stages))
       (list? (.ref value 'profile-bindings))
       (list? (.ref value 'provenance))
       (= (length (.ref value 'profiles))
          (length (.ref value 'provenance)))
       (eq? (.ref value 'runtime-executed?) #f)))

(define-type (YuanxuProfileBundle @ Type.)
  .element?: yuanxu-profile-bundle-shape?)

(def (yuanxu-profile-composition-strategy-shape? value)
  (and (yuanxu-object-shape?
        value
        +yuanxu-profile-composition-strategy-kind+
        '(kind identity compose runtime-executed?))
       (symbol? (.ref value 'identity))
       (procedure? (.ref value 'compose))
       (eq? (.ref value 'runtime-executed?) #f)))

(define-type (YuanxuProfileCompositionStrategy @ Type.)
  .element?: yuanxu-profile-composition-strategy-shape?)

(def (yuanxu-profile-export
      identity-value profile-value
      dependency-roots: (dependency-root-values '())
      capability-requirements: (capability-values '())
      revision: (revision-value 'unversioned)
      generation: (generation-value 'initial)
      provenance: (provenance-value 'declared))
  (validate
   YuanxuProfileExport
   (.o kind: +yuanxu-profile-export-kind+
       identity: identity-value
       profile: profile-value
       dependency-roots: dependency-root-values
       capability-requirements: capability-values
       revision: revision-value
       generation: generation-value
       provenance: provenance-value
       runtime-executed?: #f)))

;;; Build the export index once.  Selection performs O(1) membership lookup and
;;; never reconstructs or rescans a Module export surface.
(def (yuanxu-module-profiles . export-values)
  (unless (every (cut element? YuanxuProfileExport <>) export-values)
    (error "Module profiles require typed Profile exports" export-values))
  (let ((index (make-hash-table-eq))
        (prototype (yuanxu-empty-profiles)))
    (for-each
     (lambda (export-value)
       (let (export-identity-value (.ref export-value 'identity))
         (when (hash-key? index export-identity-value)
           (error "duplicate Module Profile export" export-identity-value))
         (hash-put! index export-identity-value export-value)))
     export-values)
    (.o (:: @ prototype)
        contributions: export-values
        export-index: index)))

(def (yuanxu-profile-selection-proof
      module-definition-value module-instance-value export-value)
  (validate
   YuanxuProfileSelectionProof
   (.o kind: +yuanxu-profile-selection-proof-kind+
       module-definition: module-definition-value
       module-instance: module-instance-value
       profile-identity: (.ref export-value 'identity)
       profile-export: export-value
       revision: (.ref export-value 'revision)
       generation: (.ref export-value 'generation)
       accepted?: #t
       diagnostics: '()
       runtime-executed?: #f)))

(def (yuanxu-profile-bundle
      module-bindings-value profile-values profile-identity-values
      import-values capability-values proof-values stage-values
      profile-binding-values provenance-values)
  (validate
   YuanxuProfileBundle
   (.o kind: +yuanxu-profile-bundle-kind+
       module-bindings: module-bindings-value
       profiles: profile-values
       profile-identities: profile-identity-values
       imports: import-values
       capabilities: capability-values
       selection-proofs: proof-values
       stages: stage-values
       profile-bindings: profile-binding-values
       provenance: provenance-values
       runtime-executed?: #f)))

(def (yuanxu-profile-bundle? value)
  (element? YuanxuProfileBundle value))

(def (yuanxu-profile-ref/default profile slot default)
  (if (.slot? profile slot) (.ref profile slot) default))

;;; Stage spaces are POO objects whose slot names are Scenario stage names.
;;; Earlier operands retain normal composition precedence; a derived Profile
;;; refines a stage explicitly with native `=>.+` before entering this merge.
;;; Empty Stage spaces carry no semantics, so discard them before asking the
;;; native POO engine for one flat precedence list.  This avoids manufacturing
;;; one empty object and one prototype layer per selected Profile.
(def (yuanxu-compose-stage-spaces stage-spaces)
  (let (effective-stage-spaces
        (filter-map
         (lambda (stage-space)
           (unless (object? stage-space)
             (error "Profile stages must be a POO slot space" stage-space))
           (and (pair? (.all-slots stage-space)) stage-space))
         stage-spaces))
    (if (null? effective-stage-spaces)
      (.o)
      (apply .mix effective-stage-spaces))))

(def (yuanxu-profile-export-ref profiles-value profile-identity)
  (unless (and (object? profiles-value)
               (.slot? profiles-value 'export-index))
    (error "Module does not publish an indexed Profile export surface"
           profiles-value))
  (let (index (.ref profiles-value 'export-index))
    (unless (hash-key? index profile-identity)
      (error "Profile is not exported by Module" profile-identity))
    (hash-get index profile-identity)))

;;; Selection is intentionally shallow: dependency closure and cycle handling
;;; remain owned by selected Graph admission after the root is admitted.
(def (yuanxu-select-module-profiles module-value instance-identity profile-identities)
  (unless (element? SemanticModuleContract module-value)
    (error "use-module requires a semantic Module" module-value))
  (unless (and (or (symbol? instance-identity)
                   (object? instance-identity))
               (pair? profile-identities)
               (every symbol? profile-identities))
    (error "use-module requires an instance identity and exported Profiles"
           instance-identity profile-identities))
  (let* ((selected-profile-identities
          (delete-duplicates/hash profile-identities from-end?: #t))
         (module-definition (.ref module-value 'identity))
         (instance-name
          (if (symbol? instance-identity)
            instance-identity
            (.ref instance-identity 'name)))
         (module-profiles (.ref module-value 'profiles))
         (exports
          (map (cut yuanxu-profile-export-ref module-profiles <>)
               selected-profile-identities))
         (profile-values (map (cut .ref <> 'profile) exports))
         (proof-values
          (map (cut yuanxu-profile-selection-proof
                    module-definition instance-identity <>)
               exports))
         (stage-values
          (yuanxu-compose-stage-spaces
           (filter-map
            (lambda (profile)
              (and (.slot? profile 'stages) (.ref profile 'stages)))
            profile-values))))
    (yuanxu-profile-bundle
     (list (yuanxu-scenario-module-binding instance-name module-value))
     profile-values
     selected-profile-identities
     (append-map (cut .ref <> 'dependency-roots) exports)
     (append-map (cut .ref <> 'capability-requirements) exports)
     proof-values
     stage-values
     (map (cut yuanxu-scenario-profile-binding instance-name <>)
          selected-profile-identities)
     (map (cut .ref <> 'provenance) exports))))

(def (yuanxu-profile-identity profile)
  (let* ((identity-value
          (and (.slot? profile 'identity) (.ref profile 'identity)))
         (name-value
          (and (.slot? profile 'name) (.ref profile 'name))))
    (cond
     ((symbol? identity-value) identity-value)
     ((and (string? identity-value) (> (string-length identity-value) 0))
      (string->symbol identity-value))
     ((symbol? name-value) name-value)
     (else
      (error "Profile operand requires a symbolic or string identity"
             identity-value name-value)))))

(def (yuanxu-direct-profile-bundle profile)
  (unless (object? profile)
    (error "profiles composition accepts only POO-native Profile values"
           profile))
  (let (profile-identity-value (yuanxu-profile-identity profile))
    (yuanxu-profile-bundle
     '()
     (list profile)
     (list profile-identity-value)
     (yuanxu-profile-ref/default profile 'imports '())
     (yuanxu-profile-ref/default profile 'capabilities '())
     '()
     (yuanxu-profile-ref/default profile 'stages (.o))
     '()
     (list (yuanxu-profile-ref/default profile 'provenance 'declared)))))

(def (yuanxu-profile-bundle-selection-keys bundle)
  (if (pair? (.ref bundle 'selection-proofs))
    (map (lambda (proof)
           (list (.ref proof 'module-instance)
                 (.ref proof 'profile-identity)))
         (.ref bundle 'selection-proofs))
    (map (cut list 'direct <>) (.ref bundle 'profile-identities))))

;;; Fuse operands in source order while using one hash index for idempotence.
;;; The first admitted selection owns its stable position and evidence.
(def (yuanxu-compose-profile-bundles operand-values)
  (unless (pair? operand-values)
    (error "compose profiles requires at least one Profile operand"))
  (let ((seen (make-hash-table))
        (module-seen (make-hash-table))
        (import-seen (make-hash-table))
        (capability-seen (make-hash-table))
        (module-bindings-rev '())
        (profiles-rev '())
        (profile-identities-rev '())
        (imports-rev '())
        (capabilities-rev '())
        (proofs-rev '())
        (stage-spaces-rev '())
        (profile-bindings-rev '())
        (provenance-rev '()))
    (for-each
     (lambda (operand)
       (let* ((bundle
               (if (yuanxu-profile-bundle? operand)
                 operand
                 (yuanxu-direct-profile-bundle operand)))
              (keys (yuanxu-profile-bundle-selection-keys bundle)))
         (for-each
          (lambda (key profile identity proof profile-binding provenance)
            (if (hash-key? seen key)
              (let (previous (hash-get seen key))
                (if proof
                  (unless (and previous
                               (eq? (.ref previous 'revision)
                                    (.ref proof 'revision))
                               (eq? (.ref previous 'generation)
                                    (.ref proof 'generation)))
                    (yuanxu-raise-profile-composition-conflict
                     identity 'selection-revision
                     (.o previous-revision: (.ref previous 'revision)
                         previous-generation: (.ref previous 'generation)
                         candidate-revision: (.ref proof 'revision)
                         candidate-generation: (.ref proof 'generation))
                     previous proof))
                  (unless (eq? previous profile)
                    (yuanxu-raise-profile-composition-conflict
                     identity 'distinct-direct-values
                     'one-profile-value-per-identity
                     previous profile))))
              (begin
              (hash-put! seen key (or proof profile))
              (set! profiles-rev (cons profile profiles-rev))
              (set! profile-identities-rev
                    (cons identity profile-identities-rev))
              (when proof (set! proofs-rev (cons proof proofs-rev)))
              (when profile-binding
                (set! profile-bindings-rev
                      (cons profile-binding profile-bindings-rev)))
              (set! provenance-rev (cons provenance provenance-rev)))))
          keys
          (.ref bundle 'profiles)
          (.ref bundle 'profile-identities)
          (if (pair? (.ref bundle 'selection-proofs))
            (.ref bundle 'selection-proofs)
            (make-list (length keys) #f))
          (if (pair? (.ref bundle 'profile-bindings))
            (.ref bundle 'profile-bindings)
            (make-list (length keys) #f))
          (.ref bundle 'provenance))
         (for-each
         (lambda (module-binding)
            (let (key (.ref module-binding 'alias))
              (if (hash-key? module-seen key)
                (unless (eq? (.ref (hash-get module-seen key) 'module)
                             (.ref module-binding 'module))
                  (error "distinct Modules share one composition instance"
                         key
                         (hash-get module-seen key)
                         module-binding))
                (begin
                  (hash-put! module-seen key module-binding)
                  (set! module-bindings-rev
                        (cons module-binding module-bindings-rev))))))
          (.ref bundle 'module-bindings))
         (for-each
          (lambda (import-value)
            (unless (hash-key? import-seen import-value)
              (hash-put! import-seen import-value #t)
              (set! imports-rev (cons import-value imports-rev))))
          (.ref bundle 'imports))
         (for-each
          (lambda (capability-value)
            (unless (hash-key? capability-seen capability-value)
              (hash-put! capability-seen capability-value #t)
              (set! capabilities-rev
                    (cons capability-value capabilities-rev))))
          (.ref bundle 'capabilities))
         (set! stage-spaces-rev
               (cons (.ref bundle 'stages) stage-spaces-rev))))
     operand-values)
    (yuanxu-profile-bundle
     (reverse module-bindings-rev)
     (reverse profiles-rev)
     (reverse profile-identities-rev)
     (reverse imports-rev)
     (reverse capabilities-rev)
     (reverse proofs-rev)
     (yuanxu-compose-stage-spaces (reverse stage-spaces-rev))
     (reverse profile-bindings-rev)
     (reverse provenance-rev))))

(def profiles
  (validate
   YuanxuProfileCompositionStrategy
   (.o kind: +yuanxu-profile-composition-strategy-kind+
       identity: 'profiles
       compose: yuanxu-compose-profile-bundles
       runtime-executed?: #f)))

(def (compose strategy . operands)
  (unless (element? YuanxuProfileCompositionStrategy strategy)
    (error "compose requires a POO-native composition strategy" strategy))
  ((.ref strategy 'compose) operands))
