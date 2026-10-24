;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: read pinned JSON Schema source files into JSON-like Scheme data.
;;; Invariant: this owner performs file decoding only. Normalization,
;;; reference resolution, contract emission, and validation live elsewhere.

(import (only-in :std/encoding/json
                 JSONReadOptions
                 current-json-read-options
                 read-json)
        (only-in :std/list/walist
                 PureAList?
                 walist->list))

(export yuanxu-json-schema-source->json-like
        yuanxu-json-schema-read-file
        yuanxu-json-schema-read-port)

;; : (-> Pair Pair)
(def (yuanxu-json-schema-source-row->json-like row)
  (cons (car row)
        (yuanxu-json-schema-source->json-like (cdr row))))

;; : (-> JsonRuntimeDatum JsonLikeDatum)
(def (yuanxu-json-schema-source->json-like value)
  (cond
   ((PureAList? value)
    (map yuanxu-json-schema-source-row->json-like
         (walist->list value)))
   ((vector? value)
    (map yuanxu-json-schema-source->json-like
         (vector->list value)))
   ((list? value)
    (map yuanxu-json-schema-source->json-like value))
   (else value)))

;;; Boundary: the bridge consumes symbol-key walists so downstream contract
;;; logic stays independent from hash-table iteration order and string/symbol
;;; key drift.
;; : (-> InputPort JsonLikeSchema)
(def (yuanxu-json-schema-read-port port)
  (parameterize ((current-json-read-options
                  (JSONReadOptions key-as-symbol: #t)))
    (yuanxu-json-schema-source->json-like
     (read-json port))))

;; : (-> PathString JsonLikeSchema)
(def (yuanxu-json-schema-read-file path)
  (call-with-input-file path yuanxu-json-schema-read-port))
