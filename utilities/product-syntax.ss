;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: shared compile-time product projection primitives.
;;; Invariant: these helpers only lower fixed field syntax to ordinary ordered
;;; pairs; domain projection policy remains with the importing subsystem.

(export yuanxu-product-rows/tail
        yuanxu-product-rows-into/rev
        yuanxu-product-field-rows
        yuanxu-product-field-rows/tail)

;; Keep the two list operations as functions: callers may already have rows as
;; values, while the syntax helpers below own only literal field lowering.
(def (yuanxu-product-rows/tail rows tail)
  (append rows tail))

(def (yuanxu-product-rows-into/rev rows rows-rev)
  (append (reverse rows) rows-rev))

;; This is the same small product rule used by upstream gerbil-poo: each
;; declared field becomes one ordered pair, with no parallel runtime schema.
(defrule (yuanxu-product-field-rows (field value) ...)
  (list (cons 'field value) ...))

(defrule (yuanxu-product-field-rows/tail tail (field value) ...)
  (yuanxu-product-rows/tail
   (yuanxu-product-field-rows (field value) ...)
   tail))
