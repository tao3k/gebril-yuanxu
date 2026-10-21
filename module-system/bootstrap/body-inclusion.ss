;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (for-syntax :gerbil/expander))
(export include-module-body)

;;; Internal compiler projection for a relocated role root. This is the native
;;; include expansion, with headers consumed by the native Module reader. It
;;; preserves source locations, relative imports and this-source-file semantics.
(defsyntax (include-module-body stx)
  (syntax-case stx ()
    ((_ path)
     (stx-string? #'path)
     (let (path (stx-e #'path))
       (when (member path (current-expander-path))
         (raise-syntax-error #f "cyclic Module body inclusion" stx path))
       (let-values (((_prelude _id _namespace body) (core-read-module/sexp path)))
         (syntax-local-rewrap
          (stx-wrap-source (core-cons 'begin body) (stx-source stx))))))
    (_ (raise-syntax-error #f "expected a literal Module source path" stx))))
