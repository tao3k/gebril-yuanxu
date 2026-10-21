;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :clan/poo/object
        (only-in :std/text/pregexp pregexp-match)
        (only-in :clan/poo/mop define-type Type.)
        (only-in :yuanxu/types yuanxu-predicate-contract yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/modules/nix/types NixSourceContract NixFlakeSourceContract NixScopeContract)
        (only-in :yuanxu/modules/json-schema/types JsonSchemaScopeContract)
        (only-in :yuanxu/modules/json-schema/json-schema-contract yuanxu-json-schema->contract))
(export ProviderArtifactContract ProviderTypeIndexContract ProviderSelectionContract ConfigurationEnvelopeContract
        CollectionAuthorityType CollectionReceiptType OpenTofuConfigContract OpenTofuScopeContract NixScopeContract JsonSchemaScopeContract)

;; Only the OpenTofu configuration envelope belongs here. Field constraints
;; come from each demanded Provider Contract, not a second maintained table.
(def ConfigurationEnvelopeContract
  (let ((object-input '((type . "object")))
        (instances '((type . "object") (additionalProperties . ((type . "object"))))))
    (yuanxu-json-schema->contract 'opentofu/configuration-envelope
      `((type . "object") (additionalProperties . #f)
        (properties .
          ((provider . ((type . "object")
                        (additionalProperties . ((type . "array") (items . ,object-input)))))
           (resource . ((type . "object") (additionalProperties . ,instances)))
           (data . ((type . "object") (additionalProperties . ,instances)))))))))

(def ProviderSelectionContract
  (yuanxu-json-schema->contract 'opentofu/provider-selection
    '((type . "object") (additionalProperties . #f)
      (required . ("provider" "version"))
      (properties .
        ((provider . ((type . "string") (minLength . 1)))
         (version . ((type . "string")
                     (pattern . "^[0-9]+[.][0-9]+[.][0-9]+$"))))))))

;; Shape of a package-produced manifest, not an independent package lock.
(def digest-schema '((type . "string") (pattern . "^[0-9a-f]{64}$")))
(def ProviderArtifactContract
  (yuanxu-json-schema->contract 'opentofu/provider-artifact
    `((type . "object") (additionalProperties . #f)
      (required . ("format" "provider" "version" "schema-sha256" "indexes"))
      (properties .
        ((format . ((type . "string") (pattern . "^yuanxu/provider-schema-v2$")))
         (provider . ((type . "string") (minLength . 1)))
         (version . ((type . "string") (minLength . 1)))
         (schema-sha256 . ,digest-schema)
         (indexes . ((type . "object") (additionalProperties . #f)
                     (required . ("provider" "resource" "data"))
                     (properties . ((provider . ,digest-schema)
                                    (resource . ,digest-schema)
                                    (data . ,digest-schema))))))))))

(def ProviderTypeIndexContract
  (yuanxu-json-schema->contract 'opentofu/provider-type-index
    `((type . "object") (additionalProperties . #f)
      (required . ("provider" "version" "schema-sha256" "kind" "entries"))
      (properties .
        ((provider . ((type . "string") (minLength . 1)))
         (version . ((type . "string") (minLength . 1)))
         (schema-sha256 . ,digest-schema)
         (kind . ((enum . ("provider" "resource" "data"))))
         (entries . ((type . "object") (additionalProperties . ,digest-schema))))))))

(def (slots-satisfy? value requirements)
  (and (object? value)
       (every (lambda (row)
                (and (.slot? value (car row)) ((cdr row) (.ref value (car row)))))
              requirements)))

(define-type (CollectionAuthorityType @ Type.)
  .element?:
  (lambda (value)
    (slots-satisfy? value
      (list (cons 'provider string?) (cons 'version string?) (cons 'schema string?)
            (cons '.matches? procedure?) (cons '.issue procedure?) (cons '.verify procedure?)))))

;; Shape only. This Type deliberately does not authenticate a receipt.
(define-type (CollectionReceiptType @ Type.)
  .element?:
  (lambda (value)
    (slots-satisfy? value
      (list (cons 'provider string?) (cons 'version string?) (cons 'schema string?)
            (cons 'field list?) (cons 'candidate-digest string?) (cons 'expires real?)))))

;; Scope publication checks shape without demanding artifacts or activating Build.
(def OpenTofuScopeContract
  (yuanxu-predicate-contract 'opentofu/scope
    (lambda (value)
      (and (object? value)
           (every (cut .slot? value <>) '(config modules types prototypes schema .build-inputs))
           (object? (.get value config))
           (.slot? (.get value types) 'configuration)))
    (lambda (_value _context) '())))
(def OpenTofuConfigContract
  (yuanxu-predicate-contract 'opentofu/config
    (lambda (value)
      (and (object? value) (.slot? value 'artifact) (.slot? value 'source)
           (or (not (.get value artifact)) (string? (.get value artifact)))
           (or (not (.slot? value 'selection-input)) (not (.get value selection-input))
               (and (symbol? (.get value selection-input))
                    (pregexp-match "^[A-Za-z][A-Za-z0-9_-]*$"
                                   (symbol->string (.get value selection-input)))))
           (let (source (.get value source))
             (or (not source)
                 (and (object? source) (.slot? source '.prepare)
                      (procedure? (.get source .prepare))
                      (.slot? source 'source-inputs)
                      (or (yuanxu-validation-evidence-accepted? (.call NixFlakeSourceContract .admit source #f))
                          (yuanxu-validation-evidence-accepted? (.call NixSourceContract .admit source #f))))))))
    (lambda (_value _context) '())))
