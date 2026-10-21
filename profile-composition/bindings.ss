;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Inert Profile selection and lexical binding values used by composition.

(import (only-in :clan/poo/object .o .ref object?))

(export yuanxu-module-scope
        yuanxu-profile-ref
        yuanxu-scenario-module-binding
        yuanxu-scenario-profile-binding)

;; A bounded declaration binds an existing native scope, without copying it,
;; forcing publication/source slots, or manufacturing source admission evidence.
(def (yuanxu-module-scope value)
  (unless (object? value)
    (error "use-module bounded body requires a native POO scope" value))
  value)

(def (yuanxu-profile-ref module slot)
  (.ref module slot))

(def (yuanxu-scenario-module-binding alias module)
  (let ((alias-value alias)
        (module-value module))
    (.o (kind 'yuanxu.scenario.module-binding.v1)
        (alias alias-value)
        (module module-value))))

(def (yuanxu-scenario-profile-binding alias slot)
  (let ((alias-value alias)
        (slot-value slot))
    (.o (kind 'yuanxu.scenario.profile-binding.v1)
        (alias alias-value)
        (slot slot-value))))
