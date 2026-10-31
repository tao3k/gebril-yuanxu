;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Retained negative control: compiled BEFORE the store lowering pass.
(import :clan/poo/object)
(export unlowered-store-callback unlowered-carrier unlowered-invoker)
;; A runtime object slot prevents a trivial cross-module alias from being
;; inlined back into the qualified caller. The callback BODY stays unlowered.
(def Callback
  (.o writer: (lambda (spec value) ($self-slot-spec-fun-set! spec value))))
(def (unlowered-store-callback) (.get Callback writer))
(def (unlowered-carrier) (cdr (assq 'writer (object-slots Callback))))
;; Ordinary higher-order caller, compiled without store lowering. Returning it
;; from a slot prevents consumer inlining from changing the tested body.
(def Invoker (.o call: (lambda (writer spec value) (writer spec value))))
(def (unlowered-invoker) (.get Invoker call))
