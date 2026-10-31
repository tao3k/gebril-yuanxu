;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .def .get .ref)
        "types.ss" "func.ss")
(export JsonSchema.)
(.def (JsonSchema. @ (.get JsonSchemaScopeContract proto) defaults)
  read: read-schema
  normalize: normalize-schema
  compile: (lambda ((source (.ref defaults 'schema))) (compile-schema source))
  contract: (lambda (identity (source (.ref defaults 'schema))) (schema-contract identity source))
  validate: validate-schema)
