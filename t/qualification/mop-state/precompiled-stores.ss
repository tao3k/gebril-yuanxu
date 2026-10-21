;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compiled independently through the same primitive-store lowering as SDK
;;; bindings, BEFORE its consumer. No guard at the callback invocation site.
(import :clan/poo/object
        (prefix-in (only-in :gerbil/runtime/mop slot-set!) runtime.))
(export precompiled-store precompiled-subjects)
(def Callbacks
  (.o generated:
      (lambda (spec value) ($self-slot-spec-fun-set! spec value))
      reflective:
      (lambda (spec value) (runtime.slot-set! spec 'fun value))
      inline:
      (lambda (spec value) (struct-instance-init! spec value))))
(def (precompiled-store route) (.ref Callbacks route))
;; Qualification subjects use the same compiler-owned constructor phase.
(def (precompiled-subjects)
  (.def Parent port: 5432 unused: (error "unselected slot forced"))
  (.def (Hot @ Parent))
  (.def (Cold @ Parent))
  (.o parent: Parent hot: Hot cold: Cold))
