;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .cc .put! .ref) (only-in :clan/poo/mop validate)
        "types.ss" "objects.ss")
(export JsonSchemaDefaults JsonSchemaScope)
;;; An omitted schema compiles an unconstrained object. No schema is compiled
;;; while this default or the Module publication is constructed.
(def JsonSchemaDefaults (.o schema: '((type . "object"))))

;; Native role initialization owns the configured value. Each selected graph
;; independently admits it; no constructor approval crosses the source epoch.
(def JsonSchemaScope
  (let* ((configured
          (.o (:: @ JsonSchema.)
            defaults: JsonSchemaDefaults
            types: (.o source: SchemaSourceContract artifact: SchemaArtifactContract
                       config: JsonSchemaConfigContract scope: JsonSchemaScopeContract)))
         (checked (validate JsonSchemaScopeContract configured))
         (published (.cc configured)))
    ;; The configured publication owns these checked procedures as values.
    ;; Prototype refinements can still recompute the underlying role methods.
    (for-each (lambda (name) (.put! published name (.ref checked name)))
              '(read normalize compile contract validate))
    published))
