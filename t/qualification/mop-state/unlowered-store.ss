;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Retained negative control: compiled BEFORE the store lowering pass.
(import :clan/poo/object)
(export unlowered-generated-store!)
(def (unlowered-generated-store! spec value)
  ($self-slot-spec-fun-set! spec value))
