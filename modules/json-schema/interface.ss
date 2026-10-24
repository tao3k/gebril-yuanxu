;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(.def JsonSchema
  identity: 'json-schema
  core:
  (.o requires: (.o)
      scope-contract: JsonSchemaScopeContract
      exports:
      (.o (:: @ JsonSchema.)
        defaults: JsonSchemaDefaults
        types: (.o source: SchemaSourceContract artifact: SchemaArtifactContract
                   config: JsonSchemaConfigContract scope: JsonSchemaScopeContract)))
  features: (.o))
