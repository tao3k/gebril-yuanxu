;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private value projection, copied and admitted with the isolated Fixture.
(import :clan/poo/object
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-private-source)
        (only-in :yuanxu/module-system/source/reader module-prepared-source-binding)
        (only-in :yuanxu/module-system/source/admission module-source-admit-current!))
(export load-role)

(def (load-role root name names rows)
  (module-source-admit-current! rows "projected module source changed")
  (def owner (path-normalize root))
  (def prepared (yuanxu-prepare-module-private-source owner (path-expand name owner) void))
  (def binding (string->symbol (symbol->string (gensym 'RoleValues))))
  ;; Keep the native include wrapper and its issued read tokens. Only the
  ;; ordinary POO tuple of actual exports is added to the admitted role body.
  (def bundled
    (.cc prepared compiler-forms:
      (append (.get prepared compiler-forms)
        (list '(import :clan/poo/object)
              `(def ,binding (.o ,@names))))))
  (def value (module-prepared-source-binding bundled binding))
  (module-source-admit-current! rows "projected module source changed")
  value)
