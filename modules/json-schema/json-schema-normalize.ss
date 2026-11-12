;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: facade for JSON Schema normalization across parse, definition
;;; collection, and reference resolution.
;;; Invariant: this owner wires the normalization pipeline only; new parser
;;; behavior belongs in core/parse/resolve modules and runtime predicate
;;; emission belongs in json-schema-emit.

(import (only-in "./functional.ss"
                 yuanxu-contract-json-object?)
        (only-in "./json-schema-ir.ss"
                 yuanxu-json-schema-normalization-record)
        (only-in "./json-schema-normalize-core.ss"
                 +yuanxu-json-schema-missing+
                 yuanxu-json-schema-parse)
        (only-in "./json-schema-normalize-parse.ss"
                 yuanxu-json-schema-parse-definitions)
        (only-in "./json-schema-normalize-resolve.ss"
                 yuanxu-json-schema-resolve-node))

(export yuanxu-json-schema-normalize
        yuanxu-json-schema-parse
        +yuanxu-json-schema-missing+)

;; Engineering boundary: this facade only orchestrates parse, definition
;; collection, and reference resolution. It must not grow local parser logic;
;; new JSON Schema behavior belongs in the core/parse/resolve owners.

;; Boundary: normalization is orchestration only; parser, definition, and
;; resolver semantics must remain in their dedicated owners.
;; yuanxu-json-schema-normalize
;;   : (-> JsonSchema JsonSchemaNormalization)
;;   | doc m%
;;       Parse root schema, collect local definitions, resolve local references,
;;       and preserve diagnostics from each phase for proof receipt generation.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-json-schema-normalize schema)
;;       ;; => json-schema-normalization-record
;;       ```
;;     %
(def (yuanxu-json-schema-normalize schema)
  (let* ((definitions-result
          (if (yuanxu-contract-json-object? schema)
            (yuanxu-json-schema-parse-definitions schema)
            (cons '() '())))
         (root-result (yuanxu-json-schema-parse schema))
         (resolved-result
          (yuanxu-json-schema-resolve-node
           (car root-result)
           (car definitions-result)
           '())))
    (yuanxu-json-schema-normalization-record
     (car resolved-result)
     (car definitions-result)
     (append (cdr root-result)
             (cdr definitions-result)
             (cdr resolved-result)))))
