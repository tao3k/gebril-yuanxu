;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .def .o)
        (only-in "./types.ss" JsonSchemaScopeContract)
        (only-in "./config.ss" JsonSchemaScope))
(export JsonSchema)
(.def JsonSchema
  identity: 'json-schema
  tags: '(schema validation)
  core:
  (.o scope-contract: JsonSchemaScopeContract
      exports: JsonSchemaScope)
  features: (.o))
