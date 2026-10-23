;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref .slot? .all-slots object?)
        (only-in :clan/poo/mop define-type)
        (only-in :yuanxu/object-types/contracts YuanxuObjectContract. yuanxu-predicate-contract)
        (only-in "functional.ss" yuanxu-contract-json-object?)
        (only-in "json-schema-receipt.ss" yuanxu-json-schema-contract-artifact?))
(export SchemaSourceContract SchemaArtifactContract JsonSchemaConfigContract JsonSchemaScopeContract
        schema-source?)
(def (schema-source? value) (or (boolean? value) (yuanxu-contract-json-object? value)))
(def SchemaSourceContract
  (yuanxu-predicate-contract 'json-schema/source schema-source? (lambda (_value _context) '())))
(def SchemaArtifactContract
  (yuanxu-predicate-contract 'json-schema/artifact yuanxu-json-schema-contract-artifact?
                              (lambda (_value _context) '())))
(def ProcedureContract
  (yuanxu-predicate-contract 'json-schema/procedure procedure? (lambda (_value _context) '())))
(def JsonSchemaConfigContract
  (yuanxu-predicate-contract 'json-schema/config
    (lambda (value)
      (and (object? value) (.slot? value 'schema)
           (andmap (lambda (name) (eq? name 'schema)) (.all-slots value))
           (schema-source? (.ref value 'schema))))
    (lambda (_value _context) '())))
(define-type (JsonSchemaScopeContract @ YuanxuObjectContract.)
  identity: 'json-schema/scope
  proto: (.o)
  responsibilities:
  (.o defaults: JsonSchemaConfigContract
      read: ProcedureContract normalize: ProcedureContract compile: ProcedureContract
      contract: ProcedureContract validate: ProcedureContract))
