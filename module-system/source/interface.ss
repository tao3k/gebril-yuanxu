;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native authoring Interface; branding and source policy are consumer inputs.
(import (only-in :clan/poo/object .o .ref .slot? object?)
        :yuanxu/module-system/config
        (only-in :yuanxu/module-system/authoring/roles
                 yuanxu-default-module-authoring-profile))
(export yuanxu-module-interface-prototype yuanxu-module-interface
        yuanxu-module-interface? yuanxu-module-interface-id
        yuanxu-module-interface-authoring)
(def yuanxu-module-interface-prototype
  (.o (module-interface? #t)
      id: "anonymous-module-interface"
      schemas: (.o)
      (schema-index (yuanxu-module-interface-schema-index schemas))
      authoring: (yuanxu-default-module-authoring-profile)
      metadata: '()))
(def (yuanxu-module-interface id schemas metadata
                                 authoring: (authoring (yuanxu-default-module-authoring-profile)))
  (make-module-interface yuanxu-module-interface-prototype id schemas metadata authoring))
(def (yuanxu-module-interface? value)
  (and (object? value) (.slot? value 'module-interface?)
       (eq? (.ref value 'module-interface?) #t)
       (.slot? value 'id) (string? (.ref value 'id))
       (.slot? value 'authoring)))
