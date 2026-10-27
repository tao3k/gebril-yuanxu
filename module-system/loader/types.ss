;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Backend construction checks Function fields; plans retain opaque Backend values.
(import (only-in :clan/poo/mop define-type Bool Object Function)
        (only-in :clan/poo/number UInt)
        (only-in :clan/poo/type Record List OrFalse String Symbol Pair Or))
(export ModuleLoaderBackend ModuleLoadReceipt LazyLoadPlan LoaderMetadata)

;; Extensible annotation keys do not permit arbitrary procedures/objects as values.
(define-type LoaderMetadata
  (List (Pair Symbol (Or Bool Symbol String UInt))))

(define-type ModuleLoaderBackend
  (Record name: [Symbol]
          source-kind: [Symbol]
          load: [(Function (list (OrFalse Object)) (list Object))]
          metadata: [LoaderMetadata default: '()]))

(define-type ModuleLoadReceipt
  (Record source: [Object]
          module: [(OrFalse Object) default: #f]
          backend-name: [(OrFalse Symbol) default: #f]
          loaded?: [Bool default: #f]
          code: [Symbol]
          messages: [(List String) default: '()]
          metadata: [LoaderMetadata default: '()]))

(define-type LazyLoadPlan
  (Record source: [Object]
          backends: [(List Object)]
          forced?: [Bool default: #f]
          receipt: [ModuleLoadReceipt]
          metadata: [LoaderMetadata default: '()]))
