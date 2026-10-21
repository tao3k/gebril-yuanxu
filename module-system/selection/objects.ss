;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Yuanxu user-facing facts for hot-plug module selection.
;;; Invariant: this module stays below profile/doctor presentation logic.
;;; Descriptor realization stays in package-root modules.
;;; Intent: keep the downstream surface focused on Yuanxu module activation.

(import (only-in :clan/poo/object .o .ref .slot?)
        (only-in :yuanxu/object-family/syntax
                 defpoo-object-family)
        :yuanxu/utilities/final-projection-syntax
        :yuanxu/module-system/source/imports
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/selection/flags)

(export current-module-selection-policy
        yuanxu-user-config-kind
        yuanxu-user-module-selection-kind
        yuanxu-user-config-presentation-kind
        yuanxuUserConfig
        yuanxu-user-config?
        yuanxu-user-config-modules
        yuanxu-user-config-settings
        yuanxu-user-config-module-keys
        yuanxu-user-module-bundles->modules
        yuanxu-user-module-bundles-extend
        yuanxu-user-module-selections-extend
        yuanxu-user-module-selection-extend
        yuanxu-user-module-selection-extend-flags
        yuanxu-user-module-selection->alist
        yuanxu-user-module-selection?
        yuanxu-user-module-selection-key
        yuanxu-user-module-selection-flags
        yuanxu-user-module-selection-source-ref
        yuanxu-user-module-selection-entrypoint
        yuanxu-user-module-selection-has-flag?
        yuanxu-user-module-selection-has-flags?
        yuanxu-user-module-selection-flag-entry
        yuanxu-user-module-selection-feature-fact
        yuanxu-user-module-selection
        yuanxu-user-custom-module-selection
        yuanxu-user-custom-modules-selection
        yuanxu-user-module-selection-feature?
        yuanxu-user-modules-feature?
        yuanxu-user-config-feature?
        yuanxu-user-config-feature-facts
        yuanxu-settings
        yuanxu-user-settings->alist
        yuanxu-modules-system-use-module-group
        yuanxu-modules-system-use-module
        yuanxu-user-module-bundle
        yuanxu-user-module-when)

;;; Boundary: public ids are receipt vocabulary, not runtime owners.
;; : (-> Unit YuanxuUserConfigKind)
(def yuanxu-user-config-kind
  "yuanxu.modules.user-config.v1")

;;; Module selections are user-facing hot-plug facts, so their kind id stays
;;; separate from realized descriptor and module contract ids.
;; : (-> Unit YuanxuUserModuleSelectionKind)
(def yuanxu-user-module-selection-kind
  "yuanxu.modules.user-selection.v1")

;;; Presentation ids are user-facing doctor data, not activation receipts.
;; : (-> Unit YuanxuUserConfigPresentationKind)
(def yuanxu-user-config-presentation-kind
  "yuanxu.modules.user-config.presentation.v1")

;;; Boundary: user modules are hot-plug selections, not descriptors.
;; : (-> Symbol Symbol [Symbol] MaybePooModuleSourceRef MaybePath POOObject)
(def (yuanxu-user-module-selection/source
      group
      module
      flags
      source-ref-value
      entrypoint-value)
  (.o kind: yuanxu-user-module-selection-kind
      user-group: group
      user-module: module
      selection-flags: flags
      source-ref: source-ref-value
      entrypoint: entrypoint-value
      enabled?: #t))

;;; The short constructor is the normal user-facing path for root init rows; it
;;; intentionally leaves source and entrypoint empty until custom modules opt in.
;; : (-> Symbol Symbol [Symbol] POOObject)
(def (yuanxu-user-module-selection group module flags)
  (yuanxu-user-module-selection/source group module flags 'none 'none))

;;; Custom module selections mirror Doom private modules: init.ss selects the
;;; module, and the user-owned directory contributes interface.ss as entrypoint.
;; : (-> Symbol Path [Symbol] POOObject)
(def (yuanxu-user-custom-module-selection module module-root-path flags)
  (yuanxu-user-module-selection/source
   'custom
   module
   flags
   (make-yuanxu-module-custom-interface-source module-root-path)
   (yuanxu-module-custom-interface-entrypoint module-root-path)))

;;; An anonymous @ row denotes a complete modules directory. It remains one
;;; declaration value until yuanxu-module-source-collection-interfaces discovers its child module trees.
(def (yuanxu-user-custom-modules-selection modules-root-path flags)
  (yuanxu-user-module-selection/source
   'custom
   'modules
   flags
   (make-yuanxu-module-custom-collection-source modules-root-path)
   'discover))

;;; Module-name routing keeps the user DSL on concrete modules such as
;;; `(use-module nono-sandbox ...)`, while the profile data still stores the
;;; canonical group/module key used by feature checks and presentation.
;; : (-> Symbol Symbol)
(def current-module-selection-policy (make-parameter (.o groups: (.o))))

(def (yuanxu-modules-system-use-module-group module)
  (let (groups (.ref (current-module-selection-policy) 'groups))
    (if (.slot? groups module) (.ref groups module) 'custom)))

;; : (-> Symbol [UserModuleFlagEntry] [PooUserModuleSelection])
(def (yuanxu-modules-system-use-module module flags)
  (list
   (yuanxu-user-module-selection
    (yuanxu-modules-system-use-module-group module)
    module
    flags)))

;;; Doom-style module bundles keep the user surface compact: users write
;;; unquoted group/module/flag symbols, while upstream stores plain data.
;; | UserModuleBundleClause = (Group Module Flag...)
;; yuanxu-user-module-bundle
;;   : (-> UserModuleBundleClause... [YuanxuUserModuleSelection])
;;   | contract: produces user selections only, never descriptors
;;   | doc m%
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-user-module-bundle
;;         (flow workflow +typed-receipts)
;;         (sandbox marlin +nono +cube +doctor))
;;       ;; => selections
;;       ```
;;     %
(defrules yuanxu-user-module-bundle (custom)
  ((_)
   '())
  ((_ (custom module module-root-path flag ...) module-clause ...)
   (cons (yuanxu-user-custom-module-selection
          'module
          module-root-path
          (list 'flag ...))
         (yuanxu-user-module-bundle module-clause ...)))
  ((_ (group module flag ...) module-clause ...)
   (cons (yuanxu-user-module-selection 'group 'module (list 'flag ...))
         (yuanxu-user-module-bundle module-clause ...))))

;;; Conditional module bundles mirror Doom-style feature gates while remaining
;;; ordinary Scheme control flow at the user declaration site.
;; | UserModuleCondition = Boolean
;; yuanxu-user-module-when
;;   : (-> UserModuleCondition UserModuleBundleClause... [YuanxuUserModuleSelection])
;;   | contract: false conditions return an empty selection list
;;   | doc m%
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-user-module-when enable-sandbox?
;;         (sandbox marlin +doctor))
;;       ;; => selections-or-empty
;;       ```
;;     %
(defrules yuanxu-user-module-when ()
  ((_ condition module-clause ...)
   (if condition
     (yuanxu-user-module-bundle module-clause ...)
     '())))

;; : (-> PooUserModuleSelectionCandidate Boolean)
(defpoo-object-family yuanxu-user-module-selection-kind
  yuanxu-user-module-selection?
  (accessors
   (yuanxu-user-module-selection-flags selection-flags))
  (projections))

;; : (-> POOObject Pair)
(def (yuanxu-user-module-selection-key selection)
  (cons (.ref selection 'user-group)
        (.ref selection 'user-module)))

;;; Selection extension is declaration-layer normalization only; the result is
;;; still a user selection and is not a descriptor or activation closure.
;; : (-> PooUserModuleSelection PooUserModuleSelection PooUserModuleSelection)
(def (yuanxu-user-module-selection-extend base-selection extra-selection)
  (yuanxu-user-module-selection/source
   (.ref base-selection 'user-group)
   (.ref base-selection 'user-module)
   (yuanxu-user-module-selection-extend-flags
    (yuanxu-user-module-selection-flags base-selection)
    (yuanxu-user-module-selection-flags extra-selection))
   (yuanxu-user-module-selection-extend-slot
    (.ref base-selection 'source-ref)
    (.ref extra-selection 'source-ref))
   (yuanxu-user-module-selection-extend-slot
    (.ref base-selection 'entrypoint)
    (.ref extra-selection 'entrypoint))))

;;; A matching `(group . module)` row is updated in place so extension profiles
;;; do not manufacture duplicate-module warnings for intentional flag patches.
;; : (-> [PooUserModuleSelection] PooUserModuleSelection [PooUserModuleSelection])
(def (yuanxu-user-module-selections-extend-one selections extra-selection)
  (cond
   ((null? selections) (list extra-selection))
   ((equal? (yuanxu-user-module-selection-key (car selections))
            (yuanxu-user-module-selection-key extra-selection))
    (cons (yuanxu-user-module-selection-extend (car selections) extra-selection)
          (cdr selections)))
   (else
    (cons (car selections)
          (yuanxu-user-module-selections-extend-one
           (cdr selections)
           extra-selection)))))

;;; The fold is explicit to keep declaration order stable and visible in
;;; downstream presentation receipts.
;; : (-> [PooUserModuleSelection] [PooUserModuleSelection] [PooUserModuleSelection])
(def (yuanxu-user-module-selections-extend/add normalized extra-selections)
  (cond
   ((null? extra-selections) normalized)
   (else
    (yuanxu-user-module-selections-extend/add
     (yuanxu-user-module-selections-extend-one normalized (car extra-selections))
     (cdr extra-selections)))))

;;; Public selection extension stays below profile construction so callers can
;;; normalize bundles without importing profile or doctor presentation logic.
;; : (-> [PooUserModuleSelection] [PooUserModuleSelection] [PooUserModuleSelection])
(def (yuanxu-user-module-selections-extend base-selections extra-selections)
  (yuanxu-user-module-selections-extend/add base-selections extra-selections))

;;; Bundle reconstruction keeps the public profile shape intact after extension
;;; normalization; each normalized selection becomes one declarative bundle row.
;; : (-> [PooUserModuleSelection] [[PooUserModuleSelection]])
(def (yuanxu-user-module-selections->bundles selections)
  (map list selections))

;;; Profile extension produces normalized bundles so user-visible optional flags
;;; can patch kernel modules without surfacing duplicate-module diagnostics.
;; : (-> [[PooUserModuleSelection]] [[PooUserModuleSelection]] [[PooUserModuleSelection]])
(def (yuanxu-user-module-bundles-extend base-bundles extra-bundles)
  (yuanxu-user-module-selections->bundles
   (yuanxu-user-module-selections-extend
    (yuanxu-user-module-bundles->modules base-bundles)
    (yuanxu-user-module-bundles->modules extra-bundles))))

;;; Boundary: user module selection source ref is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> POOObject MaybePooModuleSourceRef)
(def (yuanxu-user-module-selection-source-ref selection)
  (let ((source-ref (.ref selection 'source-ref)))
    (if (eq? source-ref 'none) #f source-ref)))

;;; Boundary: user module selection entrypoint is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> POOObject MaybePath)
(def (yuanxu-user-module-selection-entrypoint selection)
  (let ((entrypoint (.ref selection 'entrypoint)))
    (if (eq? entrypoint 'none) #f entrypoint)))

;; : (-> UserModuleFlagEntry Symbol Boolean)
(def (yuanxu-user-module-selection-flag-entry? entry flag)
  (or (equal? entry flag)
      (and (pair? entry)
           (equal? (car entry) flag))))

;;; Flag lookup accepts either a bare flag or a pair-shaped flag entry, because
;;; user declarations may attach metadata while predicates still answer yes/no.
;; yuanxu-user-module-selection-has-flag?
;;   : (-> POOObject Symbol Boolean)
;;   | contract: checks declared user-module flags without descriptor realization
;;   | doc m%
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-user-module-selection-has-flag? selection '+doctor)
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-user-module-selection-has-flag? selection flag)
  (and (find (lambda (entry)
               (yuanxu-user-module-selection-flag-entry? entry flag))
             (yuanxu-user-module-selection-flags selection))
       #t))

;;; Flag entry lookup returns the raw flag payload so nested declarations such
;;; as =(+cicd ...)= can be presented without descriptor realization.
;; : (-> Symbol [UserModuleFlagEntry] MaybeUserModuleFlagEntry)
(def (yuanxu-user-module-selection-flag-entry/find flag flags)
  (cond
   ((null? flags) #f)
   ((yuanxu-user-module-selection-flag-entry? (car flags) flag)
    (car flags))
   (else
    (yuanxu-user-module-selection-flag-entry/find flag (cdr flags)))))

;; : (-> POOObject Symbol MaybeUserModuleFlagEntry)
(def (yuanxu-user-module-selection-flag-entry selection flag)
  (yuanxu-user-module-selection-flag-entry/find
   flag
   (yuanxu-user-module-selection-flags selection)))

;;; User-interface presentation must show the config body the user wrote, not
;;; the resolved backend profile objects used for validation and runtime handoff.
;; : (-> Symbol Boolean)
(def (yuanxu-user-module-selection-presentation-config-flag? flag-key)
  (or (equal? flag-key ':binding)
      (equal? flag-key ':config)
      (equal? flag-key ':backend-capability-registry)
      (equal? flag-key ':user-config)))

;;; Boundary: user module selection presentation flags is the policy-visible
;;; edge for module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;;; Boundary: user module selection presentation flags drop config is the
;;; policy-visible edge for module-system behavior, keeping validation, lookup,
;;; or projection responsibilities centralized for callers.
;; : (-> [UserModuleFlagEntry] [UserModuleFlagEntry])
(def (yuanxu-user-module-selection-presentation-flags/drop-config flags)
  (cond
   ((null? flags) '())
   ((and (pair? (car flags))
         (yuanxu-user-module-selection-presentation-config-flag?
          (caar flags)))
    (yuanxu-user-module-selection-presentation-flags/drop-config
     (cdr flags)))
   (else
    (cons (car flags)
          (yuanxu-user-module-selection-presentation-flags/drop-config
           (cdr flags))))))

;;; Boundary: user module selection presentation flags is the policy-visible
;;; edge for module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> PooUserModuleSelection [UserModuleFlagEntry])
(def (yuanxu-user-module-selection-presentation-flags selection)
  (let* ((flags (yuanxu-user-module-selection-flags selection))
         (user-config-entry
          (yuanxu-user-module-selection-flag-entry/find ':user-config flags)))
    (if (and user-config-entry (pair? user-config-entry))
      (append
       (yuanxu-user-module-selection-presentation-flags/drop-config flags)
       (list (cons ':config (cdr user-config-entry))))
      flags)))

;;; Multiple-flag checks keep callers from reimplementing list scans when they
;;; need to test a declared module mode such as `+strategy +policy`.
;; : (-> POOObject [Symbol] Boolean)
(def (yuanxu-user-module-selection-has-flags? selection flags)
  (cond
   ((null? flags) #t)
   ((yuanxu-user-module-selection-has-flag? selection (car flags))
    (yuanxu-user-module-selection-has-flags? selection (cdr flags)))
   (else #f)))

;;; Boundary: a feature is a selected module plus flags in the user declaration
;;; layer. This mirrors Doom's convenient predicate shape without inheriting
;;; Doom's package or load-cache semantics.
;; : (-> PooUserModuleSelection Symbol Symbol [Symbol] Boolean)
(def (yuanxu-user-module-selection-feature? selection group module flags)
  (and (equal? (yuanxu-user-module-selection-key selection)
               (cons group module))
       (yuanxu-user-module-selection-has-flags? selection flags)))

;;; Module-list feature checks are used by profiles and config projections so
;;; downstream tooling can ask about capabilities without realizing descriptors.
;; : (-> [PooUserModuleSelection] Symbol Symbol Symbol... Boolean)
(def (yuanxu-user-modules-feature? selected-modules group module . flags)
  (cond
   ((null? selected-modules) #f)
   ((yuanxu-user-module-selection-feature? (car selected-modules)
                                             group
                                             module
                                             flags)
    #t)
   (else
    (apply yuanxu-user-modules-feature?
           (cdr selected-modules)
           group
           module
           flags))))

;;; Config-level feature checks are the stable public predicate for user tools;
;;; callers pass declared group/module/flags and receive a pure Boolean fact.
;; : (-> PooUserConfig Symbol Symbol Symbol... Boolean)
(def (yuanxu-user-config-feature? config group module . flags)
  (apply yuanxu-user-modules-feature?
         (yuanxu-user-config-modules config)
         group
         module
         flags))

;;; Loop-engine sections keep workflow-owned loop configuration visible without

;; : (-> [Value] [PooSandboxProfile])

;; : (-> [Value] [Value] Symbol)


;;; Boundary: indexed feature facts preserve init.ss declaration order for help
;;; and doctor output. The index is explanatory metadata only; resolver and
;;; loader code remain responsible for any later execution ordering.
;; : (-> PooUserModuleSelection MaybeInteger Alist)
(defpoo-final-projection
  yuanxu-user-module-selection-feature-fact/index (selection index)
  (bindings ())
  (fields ((declaration-index index)
           (declaration-phase 'init-selection)
           (key (yuanxu-user-module-selection-key selection))
           (group (.ref selection 'user-group))
           (module (.ref selection 'user-module))
           (flags
            (yuanxu-user-module-selection-presentation-flags selection))
           (source-ref
            (yuanxu-user-module-selection-source-ref-alist selection))
           (entrypoint
            (yuanxu-user-module-selection-entrypoint selection))
           (package-management? #f)
           (dependency-installation? #f)
           (descriptor-realized? #f)
           (loader-executed? #f))))

;;; Single-selection facts are useful for focused assertions where no profile
;;; order exists yet, so the declaration index is intentionally absent.
;; : (-> PooUserModuleSelection Alist)
(def (yuanxu-user-module-selection-feature-fact selection)
  (yuanxu-user-module-selection-feature-fact/index selection #f))

;;; Config feature facts preserve declaration order so help and doctor output
;;; stay aligned with the user's init.ss rows.
;; : (-> [PooUserModuleSelection] Integer [Alist])
(def (yuanxu-user-config-feature-facts/add selected-modules index)
  (cond
   ((null? selected-modules) '())
   (else
    (cons (yuanxu-user-module-selection-feature-fact/index
           (car selected-modules)
           index)
          (yuanxu-user-config-feature-facts/add
           (cdr selected-modules)
           (+ index 1))))))

;; : (-> PooUserConfig [Alist])
(def (yuanxu-user-config-feature-facts config)
  (yuanxu-user-config-feature-facts/add
   (yuanxu-user-config-modules config)
   0))

;;; Boundary: user module selection source ref projection is the policy-visible
;;; edge for module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> PooUserModuleSelection MaybeAlist)
(def (yuanxu-user-module-selection-source-ref-alist selection)
  (let ((source-ref (yuanxu-user-module-selection-source-ref selection)))
    (if source-ref
      (yuanxu-module-source-ref->alist source-ref)
      #f)))

;;; Selection presentation keeps hot-plug choices inspectable without resolving
;;; them into descriptors or touching upstream catalogs.
;; : (-> PooUserModuleSelection Alist)
(defpoo-final-projection
  yuanxu-user-module-selection->alist (selection)
  (bindings ())
  (fields ((group (.ref selection 'user-group))
           (module (.ref selection 'user-module))
           (key (yuanxu-user-module-selection-key selection))
           (source-ref
            (yuanxu-user-module-selection-source-ref-alist selection))
           (entrypoint
            (yuanxu-user-module-selection-entrypoint selection))
           (flags
            (yuanxu-user-module-selection-presentation-flags selection))
           (enabled? (.ref selection 'enabled?)))))

;;; Settings deliberately remain a plain POO slot object: this layer captures
;;; user-authored option facts, while option merge semantics stay in the module
;;; system evaluator.
;; | UserSettingSyntax = SlotKeyword Value ...
;; yuanxu-settings
;;   : (-> UserSettingSyntax POOObject)
;;   | contract: captures user settings without validating option schemas
;;   | doc m%
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-settings timeout: 30 retries: 2)
;;       ;; => settings
;;       ```
;;     %
(defrules yuanxu-settings ()
  ((_ setting ...)
   (.o setting ...)))

;;; Empty profiles are legal for tests and downstream bootstrap templates.
;; yuanxu-user-module-bundles->modules
;;   : (-> [[PooUserModuleSelection]] [PooUserModuleSelection])
;;   | doc m%
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-user-module-bundles->modules [[a b] [c]])
;;       ;; => [a b c]
;;       ```
;;     %
(def (yuanxu-user-module-bundle->modules/rev modules modules-rev)
  (if (null? modules)
    modules-rev
    (yuanxu-user-module-bundle->modules/rev
     (cdr modules)
     (cons (car modules) modules-rev))))

;; : (-> [[PooUserModuleSelection]] [PooUserModuleSelection] [PooUserModuleSelection])
(def (yuanxu-user-module-bundles->modules/rev module-bundles modules-rev)
  (if (null? module-bundles)
    modules-rev
    (yuanxu-user-module-bundles->modules/rev
     (cdr module-bundles)
     (yuanxu-user-module-bundle->modules/rev
      (car module-bundles)
      modules-rev))))

(def (yuanxu-user-module-bundles->modules module-bundles)
  (reverse
   (yuanxu-user-module-bundles->modules/rev module-bundles '())))

;;; Boundary: top-level user config groups module choices and strategy settings.
;; : (-> [PooUserModuleSelection] POOObject POOObject)
(def (yuanxuUserConfig modules settings)
  (.o kind: yuanxu-user-config-kind
      user-modules: modules
      user-settings: settings))

;; : (-> PooUserConfigCandidate Boolean)
(defpoo-object-family yuanxu-user-config-kind
  yuanxu-user-config?
  (accessors
   (yuanxu-user-config-modules user-modules)
   (yuanxu-user-config-settings user-settings))
  (projections))

;;; Module key projection is a user-facing summary for selected groups and
;;; names. It intentionally drops flags because flag checks stay per selection.
;; : (-> [PooUserModuleSelection] [Pair] [Pair])
(def (yuanxu-user-config-module-keys/rev modules keys-rev)
  (if (null? modules)
    keys-rev
    (yuanxu-user-config-module-keys/rev
     (cdr modules)
     (cons (yuanxu-user-module-selection-key (car modules)) keys-rev))))

;; : (-> PooUserConfig [Pair])
(def (yuanxu-user-config-module-keys config)
  (reverse
   (yuanxu-user-config-module-keys/rev
    (yuanxu-user-config-modules config)
    '())))

;;; Settings presentation is intentionally shallow: user settings remain slots,
;;; while schema validation and merge semantics belong to upstream descriptors.
;; : (-> POOObject [Symbol] Alist Alist)
(def (yuanxu-user-settings->alist/rev settings setting-keys rows-rev)
  (if (null? setting-keys)
    rows-rev
    (yuanxu-user-settings->alist/rev
     settings
     (cdr setting-keys)
     (cons (cons (car setting-keys) (.ref settings (car setting-keys)))
           rows-rev))))

;; : (-> POOObject [Symbol] Alist)
(def (yuanxu-user-settings->alist settings setting-keys)
  (reverse
   (yuanxu-user-settings->alist/rev settings setting-keys '())))
