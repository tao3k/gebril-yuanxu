;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .cc)
        (only-in :clan/poo/mop Type Type. Function Any)
        (only-in :clan/poo/type Record String Symbol)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :yuanxu/object-types/contracts YuanxuContract.)
        (only-in "functional.ss" yuanxu-contract-json-object?)
        (only-in "json-schema-ir.ss" yuanxu-json-schema-normalization?)
        (only-in "json-schema-receipt.ss" yuanxu-json-schema-contract-artifact?)
        (only-in "json-schema-validate.ss" yuanxu-json-schema-object-contract-validation?))
(export SchemaSourceContract SchemaArtifactContract JsonSchemaConfigContract JsonSchemaScopeContract
        schema-source?)
(def (schema-source? value) (or (boolean? value) (yuanxu-contract-json-object? value)))
(def SchemaSourceContract
  (.cc Type. sexp: 'JsonSchemaSource '.element? schema-source?))
(def SchemaArtifactContract
  (.cc Type. sexp: 'JsonSchemaArtifact '.element? yuanxu-json-schema-contract-artifact?))
(def Normalization
  (.cc Type. sexp: 'JsonSchemaNormalization '.element? yuanxu-json-schema-normalization?))
(def Validation
  (.cc Type. sexp: 'JsonSchemaValidation '.element? yuanxu-json-schema-object-contract-validation?))
(def JsonSchemaConfigContract
  (.cc ObjectContract. responsibilities: (.o schema: SchemaSourceContract)))
(def ScopeFields
  (Record defaults: (list JsonSchemaConfigContract)
          read: (list (Function (list SchemaSourceContract) (list String)))
          normalize: (list (Function (list Normalization) (list SchemaSourceContract)))
          compile: (list (Function (list SchemaArtifactContract) '()
                                  optional: (list SchemaSourceContract)))
          contract: (list (Function (list Type) (list Symbol)
                                   optional: (list SchemaSourceContract)))
          validate: (list (Function (list Validation) (list SchemaArtifactContract Any)))))
;; The prototype constructs reusable native objects. The public value protocol
;; is structural and checks actual callable signatures, independent of a source
;; role's private prototype instance. Core retains source/context authority.
(def JsonSchemaScopeContract
  (.cc YuanxuContract. identity: 'json-schema/scope proto: (.o)
       value-contract: ScopeFields))
