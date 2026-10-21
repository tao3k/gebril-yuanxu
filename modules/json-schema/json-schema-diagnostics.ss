;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Structured diagnostics shared by pure node checks and Core receipt consumers.
(import (only-in "./json-schema-validation-core.ss" yuanxu-json-schema-path->symbol))
(export #t)

(defstruct yuanxu-json-schema-validation-diagnostic
  (severity reason message slot value contract metadata)
  transparent: #t)

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
