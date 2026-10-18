;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Structured diagnostics shared by pure node checks and Core receipt consumers.
(import (only-in "./json-schema-validation-core.ss" poo-flow-json-schema-path->symbol))
(export #t)

(defstruct poo-flow-json-schema-validation-diagnostic
  (severity reason message slot value contract metadata)
  transparent: #t)

(def (poo-flow-json-schema-validation-diagnostic->alist diagnostic)
  (list
   (cons 'severity
         (poo-flow-json-schema-validation-diagnostic-severity diagnostic))
   (cons 'reason
         (poo-flow-json-schema-validation-diagnostic-reason diagnostic))
   (cons 'message
         (poo-flow-json-schema-validation-diagnostic-message diagnostic))
   (cons 'slot
         (poo-flow-json-schema-validation-diagnostic-slot diagnostic))
   (cons 'value
         (poo-flow-json-schema-validation-diagnostic-value diagnostic))
   (cons 'contract
         (poo-flow-json-schema-validation-diagnostic-contract diagnostic))
   (cons 'metadata
         (poo-flow-json-schema-validation-diagnostic-metadata diagnostic))))

(def (poo-flow-json-schema-missing-path-diagnostic path value contract)
  (make-poo-flow-json-schema-validation-diagnostic
   'error
   'missing-required-slot
   "Required JSON Schema contract path is missing"
   (poo-flow-json-schema-path->symbol path)
   value
   contract
   `((owner . json-schema-validate)
     (path . ,path))))

(def (poo-flow-json-schema-invalid-path-diagnostic reason message path value
                                                   contract)
  (make-poo-flow-json-schema-validation-diagnostic
   'error
   reason
   message
   (poo-flow-json-schema-path->symbol path)
   value
   contract
   `((owner . json-schema-validate)
     (path . ,path))))
