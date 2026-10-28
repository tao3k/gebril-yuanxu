;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Structured diagnostics shared by pure node checks and Core receipt consumers.
(import (only-in :yuanxu/object-family/syntax defpoo-object-family))
(import (only-in "./json-schema-validation-core.ss" yuanxu-json-schema-path->symbol))
(export #t)

;; Public validation values cross source-publication epochs. Native POO
;; slots preserve their declared interface without a generative record type
;; from one reader being mistaken for the record type of another reader.
(defpoo-object-family
  (prototype JsonSchemaValidationDiagnostic
    json-schema-validation-diagnostic yuanxu-json-schema-validation-diagnostic?)
  (constructor make-yuanxu-json-schema-validation-diagnostic
    (severity-value severity)
    (reason-value reason)
    (message-value message)
    (slot-value slot)
    (value-value value)
    (contract-value contract)
    (metadata-value metadata))
  (accessors
    (yuanxu-json-schema-validation-diagnostic-severity severity)
    (yuanxu-json-schema-validation-diagnostic-reason reason)
    (yuanxu-json-schema-validation-diagnostic-message message)
    (yuanxu-json-schema-validation-diagnostic-slot slot)
    (yuanxu-json-schema-validation-diagnostic-value value)
    (yuanxu-json-schema-validation-diagnostic-contract contract)
    (yuanxu-json-schema-validation-diagnostic-metadata metadata))
  (projections))

(def (yuanxu-json-schema-validation-diagnostic->alist diagnostic)
  (list
   (cons 'severity
         (yuanxu-json-schema-validation-diagnostic-severity diagnostic))
   (cons 'reason
         (yuanxu-json-schema-validation-diagnostic-reason diagnostic))
   (cons 'message
         (yuanxu-json-schema-validation-diagnostic-message diagnostic))
   (cons 'slot
         (yuanxu-json-schema-validation-diagnostic-slot diagnostic))
   (cons 'value
         (yuanxu-json-schema-validation-diagnostic-value diagnostic))
   (cons 'contract
         (yuanxu-json-schema-validation-diagnostic-contract diagnostic))
   (cons 'metadata
         (yuanxu-json-schema-validation-diagnostic-metadata diagnostic))))

(def (yuanxu-json-schema-missing-path-diagnostic path value contract)
  (make-yuanxu-json-schema-validation-diagnostic
   'error
   'missing-required-slot
   "Required JSON Schema contract path is missing"
   (yuanxu-json-schema-path->symbol path)
   value
   contract
   `((owner . json-schema-validate)
     (path . ,path))))

(def (yuanxu-json-schema-invalid-path-diagnostic reason message path value
                                                   contract)
  (make-yuanxu-json-schema-validation-diagnostic
   'error
   reason
   message
   (yuanxu-json-schema-path->symbol path)
   value
   contract
   `((owner . json-schema-validate)
     (path . ,path))))
