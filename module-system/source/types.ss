;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Existing Module values bound to SourceRefs; construction never loads them.
(import (only-in :clan/poo/type define-type Object Record Symbol)
        (only-in :clan/poo/mop make-instance))
(export ModuleSource ModuleSourceBinding make-module-source)

(define-type ModuleSourceBinding
  (Record source: [Object] module: [Object]))

;; The exported value preserves native module identity and the owning window.
;; Consumers resolve the source declaration in the Gerbil package store.
(define-type ModuleSource
  (Record owner: [Symbol] window: [Symbol]))

(def (make-module-source owner window)
  (make-instance ModuleSource owner: owner window: window))
