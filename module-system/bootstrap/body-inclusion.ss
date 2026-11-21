;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (for-syntax :gerbil/expander))
(export include-module-body export-role-config)

;;; Internal compiler projection for a relocated role root. This is the runtime
;;; include expansion, with headers consumed by the runtime Module reader. It
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

;; The runtime expander decides whether Config is visible after body expansion.
;; No second parser for Scheme definitions, and no export of private bindings.
(defsyntax (export-role-config stx)
  (syntax-case stx ()
    ((_ name)
     (identifier? #'name)
     (if (resolve-identifier #'name)
       (syntax/loc stx (export name))
       #'(begin)))
    (_ (raise-syntax-error #f "expected the internal Config export binding" stx))))
