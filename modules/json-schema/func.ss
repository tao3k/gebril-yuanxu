;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil/core/contract using)
        "types.ss"
        (for-template "./json-schema-source.ss")
        (only-in :tao3k/yuanxu/module-system/source/deferred-declaration module-binding-action)
        (only-in :tao3k/yuanxu/module-system/source/compiled-role
                 bind-deferred-interfaces deferred-interface-values)
        (only-in "json-schema-normalize.ss" yuanxu-json-schema-normalize)
        (only-in "json-schema-receipt.ss" yuanxu-json-schema->contract-artifact yuanxu-json-schema-contract-artifact?)
        (only-in "json-schema-validate.ss" yuanxu-json-schema-contract-artifact-validate)
        (only-in "json-schema-contract.ss" yuanxu-json-schema->contract))
(export read-schema normalize-schema compile-schema schema-contract validate-schema)
(bind-deferred-interfaces
  (#f)
  (:tao3k/yuanxu/modules/json-schema/json-schema-source))

(def schema-reader
  (.o source-reader: (deferred-interface-values
                       tao3k/yuanxu/modules/json-schema/json-schema-source
                       (yuanxu-json-schema-read-file) module-binding-action)))

(def (read-schema path)
  (using (path :~ string?) ((.get schema-reader source-reader yuanxu-json-schema-read-file) path)))
(def (normalize-schema source)
  (using (source :~ schema-source?) (yuanxu-json-schema-normalize source)))
(def (compile-schema source)
  (using (source :~ schema-source?) (yuanxu-json-schema->contract-artifact source)))
(def (schema-contract identity source)
  (using ((identity :~ symbol?) (source :~ schema-source?))
    (yuanxu-json-schema->contract identity source)))
(def (validate-schema artifact candidate)
  (using (artifact :~ yuanxu-json-schema-contract-artifact?)
    (yuanxu-json-schema-contract-artifact-validate artifact candidate)))
