;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public module boundary; compilation and validation remain pure operations.
(import "json-schema-source.ss"
        "json-schema-normalize.ss"
        "json-schema-emit.ss"
        "json-schema-receipt.ss"
        "json-schema-validate.ss")
(export (import: "json-schema-source.ss")
        (import: "json-schema-normalize.ss")
        (import: "json-schema-emit.ss")
        (import: "json-schema-receipt.ss")
        (import: "json-schema-validate.ss"))
