;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: user profile objects and default config projection.
;;; Invariant: profile objects are declarative and do not realize descriptors.

(import (only-in :clan/poo/object .o .ref object?)
        :yuanxu/module-system/selection/objects)

(export yuanxu-user-profile-kind
        yuanxu-user-profile-set-kind
        yuanxu-user-profile-diagnostic-kind
        yuanxu-user-profile-presentation-kind
        yuanxu-user-profile-set-presentation-kind
        yuanxu-user-profile-policy-receipt-kind
        yuanxu-user-profile-set-policy-receipt-kind
        yuanxuUserProfile
        yuanxuUserProfileSet
        yuanxuUserProfileExtend
        yuanxuDefaultUserSettings
        yuanxu-default-user-setting-keys
        yuanxuUserConfigFromProfile
        yuanxu-user-profile?
        yuanxu-user-profile-set?
        yuanxu-user-profile-name
        yuanxu-user-profile-set-name
        yuanxu-user-profile-set-default-profile-name
        yuanxu-user-profile-set-profiles
        yuanxu-user-profile-set-profile-names
        yuanxu-user-profile-set-find-profile
        yuanxu-user-profile-set-default-profile
        yuanxu-user-profile-module-bundles
        yuanxu-user-profile-modules
        yuanxu-user-profile-settings
        yuanxu-user-profile-setting-keys
        yuanxu-user-profile-object-kind?
        yuanxu-user-profile-alist-ref)

;;; User profiles group Doom-style module bundles and settings without crossing
;;; into descriptor realization or runtime activation.
;; : (-> Unit YuanxuUserProfileKind)
(def yuanxu-user-profile-kind
  "yuanxu.modules.user-profile.v1")

;;; Profile sets model Doom's profile registry as declarative data.
;; : (-> Unit YuanxuUserProfileSetKind)
(def yuanxu-user-profile-set-kind
  "yuanxu.modules.user-profile-set.v1")

;;; Profile diagnostics are user-facing doctor facts for profile declarations.
;; : (-> Unit YuanxuUserProfileDiagnosticKind)
(def yuanxu-user-profile-diagnostic-kind
  "yuanxu.modules.user-profile.diagnostic.v1")

;;; Profile presentation ids expose the higher-level user entrypoint shape.
;; : (-> Unit YuanxuUserProfilePresentationKind)
(def yuanxu-user-profile-presentation-kind
  "yuanxu.modules.user-profile.presentation.v1")

;;; Profile set presentations expose selection state without loading profiles.
;; : (-> Unit YuanxuUserProfileSetPresentationKind)
(def yuanxu-user-profile-set-presentation-kind
  "yuanxu.modules.user-profile-set.presentation.v1")

;;; Test-time profile policy receipts are not activation receipts.
;; : (-> Unit YuanxuUserProfilePolicyReceiptKind)
(def yuanxu-user-profile-policy-receipt-kind
  "yuanxu.modules.user-profile.policy-receipt.v1")

;;; Profile-set policy receipts validate registries before selection.
;; : (-> Unit YuanxuUserProfileSetPolicyReceiptKind)
(def yuanxu-user-profile-set-policy-receipt-kind
  "yuanxu.modules.user-profile-set.policy-receipt.v1")

;;; Boundary: profile checks keep root user files independent of constructors.
;; : (-> POOObject String Boolean)
(def (yuanxu-user-profile-object-kind? value expected-kind)
  (and (object? value)
       (equal? (.ref value 'kind) expected-kind)))

;;; Boundary: user profile alist ref is the policy-visible edge for module-
;;; system, core behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> Alist Symbol Value Value)
(def (yuanxu-user-profile-alist-ref entries key default-value)
  (let (entry (assoc key entries))
    (if entry (cdr entry) default-value)))

;;; Boundary: a user profile is the Doom-style high-level entrypoint; it groups
;;; module bundles, settings, and public setting keys without realizing modules.
;; : (-> Symbol [[PooUserModuleSelection]] POOObject [Symbol] POOObject)
(def (yuanxuUserProfile name module-bundles settings setting-keys)
  (.o kind: yuanxu-user-profile-kind
      profile-name: name
      profile-selection-bundles: module-bundles
      user-settings: settings
      public-setting-keys: setting-keys))

;;; Profile sets are the Agentic AI Lab analogue of Doom's profiles.el: a named
;;; registry, a default profile key, and profile objects. No package or runtime
;;; synchronization happens here.
;; : (-> Symbol Symbol [PooUserProfile] POOObject)
(def (yuanxuUserProfileSet set-name default-name profile-list)
  (.o kind: yuanxu-user-profile-set-kind
      profile-set-name: set-name
      default-profile-name: default-name
      user-profiles: profile-list))

;;; Default user settings are upstream-owned so root init.ss can stay close to
;;; Doom's init.el: module activation only, no strategy projection details.
;; : (-> Symbol POOObject)
(def (yuanxuDefaultUserSettings profile-name)
  (yuanxu-settings
   surface: "agentic-ai-lab"
   profile: (symbol->string profile-name)
   flow-mode: 'funflow
   loop-strategy: 'governed
   sandbox-policy: 'module-gated
   sandbox-backends: '(nono cube docker)
   mode-lock: "stable"))

;; : [Symbol]
(def yuanxu-default-user-setting-keys
  '(surface
    profile
    flow-mode
    loop-strategy
    sandbox-policy
    sandbox-backends
    mode-lock))

;;; Profile projection is the only adapter from Doom-style profile data into
;;; the stable config object consumed by existing tests and tooling.
;; : (-> PooUserProfile PooUserConfig)
(def (yuanxuUserConfigFromProfile profile)
  (yuanxuUserConfig
   (yuanxu-user-profile-modules profile)
   (yuanxu-user-profile-settings profile)))

;; : (-> PooUserProfileCandidate Boolean)
(def (yuanxu-user-profile? value)
  (yuanxu-user-profile-object-kind? value yuanxu-user-profile-kind))

;; : (-> PooUserProfileSetCandidate Boolean)
(def (yuanxu-user-profile-set? value)
  (yuanxu-user-profile-object-kind? value yuanxu-user-profile-set-kind))

;; : (-> PooUserProfile Symbol)
(def (yuanxu-user-profile-name profile)
  (.ref profile 'profile-name))

;; : (-> PooUserProfileSet Symbol)
(def (yuanxu-user-profile-set-name profile-set)
  (.ref profile-set 'profile-set-name))

;; : (-> PooUserProfileSet Symbol)
(def (yuanxu-user-profile-set-default-profile-name profile-set)
  (.ref profile-set 'default-profile-name))

;; : (-> PooUserProfileSet [PooUserProfile])
(def (yuanxu-user-profile-set-profiles profile-set)
  (.ref profile-set 'user-profiles))

;;; Profile names are registry keys. They are stable user-facing selectors,
;;; matching Doom's profile name role without inheriting its env var machinery.
;; : (-> PooUserProfileSet [Symbol])
(def (yuanxu-user-profile-set-profile-names profile-set)
  (map yuanxu-user-profile-name
       (yuanxu-user-profile-set-profiles profile-set)))

;;; Profile lookup is pure data selection; missing profiles are reported by the
;;; policy path instead of triggering runtime loading.
;; : (-> Symbol [PooUserProfile] MaybePooUserProfile)
(def (yuanxu-user-profile-set-find-profile/add profile-name profiles)
  (cond
   ((null? profiles) #f)
   ((equal? profile-name (yuanxu-user-profile-name (car profiles))) (car profiles))
   (else
    (yuanxu-user-profile-set-find-profile/add profile-name (cdr profiles)))))

;; : (-> PooUserProfileSet Symbol MaybePooUserProfile)
(def (yuanxu-user-profile-set-find-profile profile-set profile-name)
  (yuanxu-user-profile-set-find-profile/add
   profile-name
   (yuanxu-user-profile-set-profiles profile-set)))

;; : (-> PooUserProfileSet MaybePooUserProfile)
(def (yuanxu-user-profile-set-default-profile profile-set)
  (yuanxu-user-profile-set-find-profile
   profile-set
   (yuanxu-user-profile-set-default-profile-name profile-set)))

;; : (-> PooUserProfile [[PooUserModuleSelection]])
(def (yuanxu-user-profile-module-bundles profile)
  (.ref profile 'profile-selection-bundles))

;; : (-> PooUserProfile [PooUserModuleSelection])
(def (yuanxu-user-profile-modules profile)
  (yuanxu-user-module-bundles->modules
   (yuanxu-user-profile-module-bundles profile)))

;; : (-> PooUserProfile POOObject)
(def (yuanxu-user-profile-settings profile)
  (.ref profile 'user-settings))

;; : (-> PooUserProfile [Symbol])
(def (yuanxu-user-profile-setting-keys profile)
  (.ref profile 'public-setting-keys))

;;; Profile extension is an upstream helper for user init surfaces. Downstream
;;; init.ss files can patch kernel module features or append custom modules
;;; without manually rebuilding config objects. The derived profile receives
;;; user defaults for its own name; kernel settings remain kernel-owned.
;; : (-> Symbol PooUserProfile [[PooUserModuleSelection]] PooUserProfile)
(def (yuanxuUserProfileExtend profile-name base-profile extra-module-bundles)
  (yuanxuUserProfile profile-name
                      (yuanxu-user-module-bundles-extend
                       (yuanxu-user-profile-module-bundles base-profile)
                       extra-module-bundles)
                      (yuanxuDefaultUserSettings profile-name)
                      yuanxu-default-user-setting-keys))
