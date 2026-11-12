;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: user module selection flag merge helpers.
;;; Invariant: helpers normalize declaration rows only; they do not realize
;;; descriptors, load modules, or inspect runtime capabilities.

(export yuanxu-user-module-selection-flag-entry-key
        yuanxu-user-module-selection-flag-key-member?
        yuanxu-user-module-selection-replace-flag
        yuanxu-user-module-values/tail
        yuanxu-user-module-selection-extend-flags/add
        yuanxu-user-module-selection-extend-flags
        yuanxu-user-module-selection-extend-slot)

;;; Flag metadata is keyed by the flag symbol so extension profiles can replace
;;; or preserve one logical flag without comparing full metadata payloads.
;; : (-> UserModuleFlagEntry Symbol)
(def (yuanxu-user-module-selection-flag-entry-key entry)
  (if (pair? entry) (car entry) entry))

;;; Membership is scoped to a flag list; it does not inspect descriptor feature
;;; facts or any realized module catalog.
;; : (-> Symbol [UserModuleFlagEntry] Boolean)
(def (yuanxu-user-module-selection-flag-key-member? flag-key flags)
  (and (member flag-key
               (map yuanxu-user-module-selection-flag-entry-key flags))
       #t))

;;; Repeated logical flag keys patch the existing slot in place. This keeps the
;;; kernel order visible while letting user init rows refine nested payloads.
;; : (-> [UserModuleFlagEntry] UserModuleFlagEntry [UserModuleFlagEntry])
(def (yuanxu-user-module-selection-replace-flag flags replacement)
  (let (replacement-key
        (yuanxu-user-module-selection-flag-entry-key replacement))
    (map (lambda (flag)
           (if (equal? (yuanxu-user-module-selection-flag-entry-key flag)
                       replacement-key)
             replacement
             flag))
         flags)))

;;; Tail append is deliberately plain functional composition. Callers keep the
;;; named helper so declaration-order policy stays visible at merge sites.
;; : (forall (a) (-> [a] [a] [a]))
(def (yuanxu-user-module-values/tail values tail)
  (append values tail))

;;; Flag extension appends unseen keys and patches seen keys in place, preserving
;;; the user-facing feature order reported by doctor and presentation output.
;; : (-> [UserModuleFlagEntry] [UserModuleFlagEntry] [UserModuleFlagEntry])
(def (yuanxu-user-module-selection-extend-flags/add normalized extra-flags)
  (foldl (lambda (extra-flag normalized*)
           (if (yuanxu-user-module-selection-flag-key-member?
                (yuanxu-user-module-selection-flag-entry-key extra-flag)
                normalized*)
             (yuanxu-user-module-selection-replace-flag normalized* extra-flag)
             (yuanxu-user-module-values/tail normalized* (list extra-flag))))
         normalized
         extra-flags))

;;; Profile extension adds feature flags to an existing module row instead of
;;; creating duplicate user selections for the same `(group . module)` key.
;; : (-> [UserModuleFlagEntry] [UserModuleFlagEntry] [UserModuleFlagEntry])
(def (yuanxu-user-module-selection-extend-flags base-flags extra-flags)
  (yuanxu-user-module-selection-extend-flags/add base-flags extra-flags))

;;; Source and entrypoint metadata remain first-writer-wins so profile
;;; extensions can add flags without silently retargeting user-owned files.
;; : (-> MaybeValue MaybeValue MaybeValue)
(def (yuanxu-user-module-selection-extend-slot base-value extra-value)
  (if (eq? base-value 'none) extra-value base-value))
