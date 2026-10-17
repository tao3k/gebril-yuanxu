;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o))
(export JsonSchemaDefaults)
;;; An omitted schema compiles an unconstrained object. No schema is compiled
;;; while this default or the Module publication is constructed.
(def JsonSchemaDefaults (.o schema: '((type . "object"))))
