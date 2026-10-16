;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native authoring Interface; branding and source policy are consumer inputs.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        :core/module-system/config
        (only-in :core/module-system/authoring/roles
                 poo-flow-default-module-authoring-profile))
(export poo-flow-module-interface-prototype poo-flow-module-interface
        poo-flow-module-interface? poo-flow-module-interface-id
        poo-flow-module-interface-authoring)
(def poo-flow-module-interface-prototype
  (.o (module-interface? #t)
      id: "anonymous-module-interface"
      schemas: (.o)
      (schema-index (poo-flow-module-interface-schema-index schemas))
      authoring: (poo-flow-default-module-authoring-profile)
      metadata: '()))
(def (poo-flow-module-interface id schemas metadata
                                 authoring: (authoring (poo-flow-default-module-authoring-profile)))
  (make-module-interface poo-flow-module-interface-prototype id schemas metadata authoring))
(def (poo-flow-module-interface? value)
  (and (object? value) (.slot? value 'module-interface?)
       (eq? (.ref value 'module-interface?) #t)
       (.slot? value 'id) (string? (.ref value 'id))
       (.slot? value 'authoring)))
