;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: test-time admission policy for module-system profiles.
;;; Invariant: diagnostics are data and never realize descriptors or runtimes.

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/list/list any filter filter-map)
        (only-in :yuanxu/module-system/selection/objects
                 yuanxu-user-module-selection-key)
        (only-in :yuanxu/profile-composition/user-profile
                 yuanxu-user-profile-diagnostic-kind
                 yuanxu-user-profile-policy-receipt-kind
                 yuanxu-user-profile-set-policy-receipt-kind
                 yuanxu-user-profile-name
                 yuanxu-user-profile-set-name
                 yuanxu-user-profile-set-default-profile-name
                 yuanxu-user-profile-set-profiles
                 yuanxu-user-profile-set-profile-names
                 yuanxu-user-profile-set-default-profile
                 yuanxu-user-profile-module-bundles
                 yuanxu-user-profile-modules
                 yuanxu-user-profile-settings
                 yuanxu-user-profile-setting-keys)
        (only-in :yuanxu/utilities/final-projection-syntax
                 defpoo-final-projection)
        (only-in :yuanxu/utilities/functional
                 yuanxu-stable-duplicates))

(export yuanxu-user-profile-policy-admit
        yuanxu-user-profile-set-policy-admit
        yuanxu-user-profile-policy-admitted?
        yuanxu-user-profile-set-policy-admitted?
        yuanxu-user-profile-diagnostics
        yuanxu-user-profile-set-diagnostics
        yuanxu-user-profile-diagnostic->alist)

;; : (-> [PooUserModuleSelection] [Pair])
(def (yuanxu-user-profile-policy-module-keys modules)
  (map yuanxu-user-module-selection-key modules))

;;; User-facing indexes make disabled bundle diagnostics stable and concise.
;; : (-> [[PooUserModuleSelection]] [Integer])
(def (yuanxu-user-profile-empty-bundle-indexes bundles)
  (filter-map
   (lambda (bundle index)
     (and (null? bundle) index))
   bundles
   (iota (length bundles))))

;;; Setting-key validation uses slot introspection instead of `.ref` so policy
;;; can report missing user settings without throwing during presentation.
;; : (-> POOObject Symbol Boolean)
(def (yuanxu-user-settings-key-present? settings key)
  (and (object? settings)
       (.slot? settings key)))

;;; Missing keys are accumulated as data because the user profile can still be
;;; presented even when it is not yet valid for activation.
;; : (-> POOObject [Symbol] [Symbol])
(def (yuanxu-user-missing-setting-keys settings setting-keys)
  (filter (lambda (key)
            (not (yuanxu-user-settings-key-present? settings key)))
          setting-keys))

;;; Profile diagnostics are plain alists so policy receipts stay cheap.
;; : (-> Symbol Symbol Symbol Alist Alist)
(defpoo-final-projection
  yuanxu-user-profile-diagnostic (severity code target detail)
  (bindings ())
  (fields ((kind yuanxu-user-profile-diagnostic-kind)
           (severity severity)
           (code code)
           (target target)
           (detail detail))))

;;; The alist projection is intentionally identity: profile diagnostics are
;;; already presentation-safe facts and should not require object realization.
;; : (-> PooUserProfileDiagnostic Alist)
(def (yuanxu-user-profile-diagnostic->alist diagnostic)
  diagnostic)

;;; Diagnostic access stays alist-based because profile policy output is printed
;;; by downstream tools; wrapping dynamic diagnostic details in POO slots makes
;;; the display path depend on object printer behavior rather than data shape.
;; : (-> PooUserProfileDiagnostic Symbol MaybeValue)
(def (yuanxu-user-profile-diagnostic-ref diagnostic key)
  (let (entry (assq key diagnostic))
    (and entry (cdr entry))))

;;; A profile with no selected modules is actionable: there is no downstream
;;; activation graph to inspect, so policy reports it as an error.
;; : (-> PooUserProfile [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-empty-diagnostics profile)
  (if (null? (yuanxu-user-profile-modules profile))
    (list
     (yuanxu-user-profile-diagnostic
      'error
      'empty-profile
      (yuanxu-user-profile-name profile)
      '((message . "profile selects no modules"))))
    '()))

;;; Disabled conditional bundles are informational, matching the expectation
;;; that user configuration may contain machine- or profile-specific branches.
;; : (-> PooUserProfile [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-empty-bundle-diagnostics profile)
  (let ((indexes
         (yuanxu-user-profile-empty-bundle-indexes
          (yuanxu-user-profile-module-bundles profile))))
    (if (null? indexes)
      '()
      (list
       (yuanxu-user-profile-diagnostic
        'info
        'inactive-module-bundle
        (yuanxu-user-profile-name profile)
        (list (cons 'bundle-indexes indexes)
              (cons 'message
                    "empty bundles are usually disabled conditions")))))))

;;; Duplicate module selections are warnings because later descriptor
;;; realization may still choose a merge policy, but users should see them.
;; : (-> PooUserProfile [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-duplicate-module-diagnostics profile)
  (let ((duplicates
         (yuanxu-stable-duplicates
          (yuanxu-user-profile-policy-module-keys
           (yuanxu-user-profile-modules profile)))))
    (if (null? duplicates)
      '()
      (list
       (yuanxu-user-profile-diagnostic
        'warning
        'duplicate-module-selection
        (yuanxu-user-profile-name profile)
        (list (cons 'module-keys duplicates)))))))

;;; Missing public setting keys are errors: presentation would otherwise need
;;; to read absent slots and fail after the policy phase.
;; : (-> PooUserProfile [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-missing-setting-diagnostics profile)
  (let ((missing
         (yuanxu-user-missing-setting-keys
          (yuanxu-user-profile-settings profile)
          (yuanxu-user-profile-setting-keys profile))))
    (if (null? missing)
      '()
      (list
       (yuanxu-user-profile-diagnostic
        'error
        'missing-setting-key
        (yuanxu-user-profile-name profile)
        (list (cons 'setting-keys missing)))))))

;;; Empty profile registries are errors because no default profile can be
;;; selected for downstream init-style composition.
;; : (-> PooUserProfileSet [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-set-empty-diagnostics profile-set)
  (if (null? (yuanxu-user-profile-set-profiles profile-set))
    (list
     (yuanxu-user-profile-diagnostic
      'error
      'empty-profile-set
      (yuanxu-user-profile-set-name profile-set)
      '((message . "profile set contains no profiles"))))
    '()))

;;; Duplicate profile names make default selection ambiguous, so the registry
;;; policy reports them before any profile is projected into config.
;; : (-> PooUserProfileSet [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-set-duplicate-name-diagnostics profile-set)
  (let ((duplicates
         (yuanxu-stable-duplicates
          (yuanxu-user-profile-set-profile-names profile-set))))
    (if (null? duplicates)
      '()
      (list
       (yuanxu-user-profile-diagnostic
        'error
        'duplicate-profile-name
        (yuanxu-user-profile-set-name profile-set)
        (list (cons 'profile-names duplicates)))))))

;;; Missing defaults are registry errors. This mirrors Doom profile startup:
;;; profile selection is explicit, but the selected profile must exist.
;; : (-> PooUserProfileSet [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-set-missing-default-diagnostics profile-set)
  (if (yuanxu-user-profile-set-default-profile profile-set)
    '()
    (list
     (yuanxu-user-profile-diagnostic
      'error
      'missing-default-profile
      (yuanxu-user-profile-set-name profile-set)
      (list
       (cons 'default-profile
             (yuanxu-user-profile-set-default-profile-name profile-set))
       (cons 'profile-names
             (yuanxu-user-profile-set-profile-names profile-set)))))))

;;; Profile policy checks declaration mistakes before descriptors are realized.
;; : (-> PooUserProfile [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-diagnostics profile)
  (append
   (yuanxu-user-profile-empty-diagnostics profile)
   (yuanxu-user-profile-empty-bundle-diagnostics profile)
   (yuanxu-user-profile-duplicate-module-diagnostics profile)
   (yuanxu-user-profile-missing-setting-diagnostics profile)))

;;; Profile set diagnostics validate the registry layer separately from each
;;; profile's module/settings declaration.
;; : (-> PooUserProfileSet [PooUserProfileDiagnostic])
(def (yuanxu-user-profile-set-diagnostics profile-set)
  (append
   (yuanxu-user-profile-set-empty-diagnostics profile-set)
   (yuanxu-user-profile-set-duplicate-name-diagnostics profile-set)
   (yuanxu-user-profile-set-missing-default-diagnostics profile-set)))

;;; Severity scanning is deliberately independent of diagnostic count: info
;;; diagnostics should remain visible without turning the profile unhealthy.
;; : (-> Symbol [PooUserProfileDiagnostic] Boolean)
(def (yuanxu-user-profile-diagnostics-has-severity? severity diagnostics)
  (any (lambda (diagnostic)
         (eq? severity
              (yuanxu-user-profile-diagnostic-ref diagnostic 'severity)))
       diagnostics))

;;; Status treats inactive conditional bundles as informational: only missing
;;; settings or duplicate selections change the actionable policy state.
;; : (-> [PooUserProfileDiagnostic] Symbol)
(def (yuanxu-user-profile-diagnostics-status diagnostics)
  (cond
   ((yuanxu-user-profile-diagnostics-has-severity? 'error diagnostics) 'error)
   ((yuanxu-user-profile-diagnostics-has-severity? 'warning diagnostics) 'warning)
   (else 'ok)))

;;; Test-time policy validates a profile before descriptor realization or
;;; runtime activation and returns a POO-native admission receipt.
;; : (-> PooUserProfile POOObject)
(def (yuanxu-user-profile-policy-admit profile)
  (let* ((diagnostics (yuanxu-user-profile-diagnostics profile))
         (status (yuanxu-user-profile-diagnostics-status diagnostics)))
    (.o kind: yuanxu-user-profile-policy-receipt-kind
        profile-name: (yuanxu-user-profile-name profile)
        policy-status: status
        admitted?: (eq? status 'ok)
        diagnostic-count: (length diagnostics)
        profile-diagnostics: diagnostics
        module-keys:
        (yuanxu-user-profile-policy-module-keys
         (yuanxu-user-profile-modules profile))
        setting-keys: (yuanxu-user-profile-setting-keys profile)
        descriptor-realized?: #f
        runtime-executed: #f)))

;;; Profile-set policy is a pure declaration receipt. It does not load files,
;;; mutate the environment, or synchronize packages.
;; : (-> PooUserProfileSet POOObject)
(def (yuanxu-user-profile-set-policy-admit profile-set)
  (let* ((diagnostics (yuanxu-user-profile-set-diagnostics profile-set))
         (status (yuanxu-user-profile-diagnostics-status diagnostics)))
    (.o kind: yuanxu-user-profile-set-policy-receipt-kind
        profile-set-name: (yuanxu-user-profile-set-name profile-set)
        default-profile-name:
        (yuanxu-user-profile-set-default-profile-name profile-set)
        profile-names: (yuanxu-user-profile-set-profile-names profile-set)
        policy-status: status
        admitted?: (eq? status 'ok)
        diagnostic-count: (length diagnostics)
        profile-diagnostics: diagnostics
        descriptor-realized?: #f
        runtime-executed: #f)))

;;; Admission predicates inspect policy receipts without presentation or CLI.
;; : (-> PooUserProfilePolicyReceipt Boolean)
(def (yuanxu-user-profile-policy-admitted? receipt)
  (.ref receipt 'admitted?))

;; : (-> PooUserProfileSetPolicyReceipt Boolean)
(def (yuanxu-user-profile-set-policy-admitted? receipt)
  (.ref receipt 'admitted?))
