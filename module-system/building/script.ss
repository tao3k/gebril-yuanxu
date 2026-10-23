;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Preserve SDK syntax and dispatch; init owns selected compilation guards.
(import (prefix-in :std/build-script sdk.)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/interface call-with-init-build-spec))
(export defbuild-script)

(defsyntax (defbuild-script stx)
  (syntax-case stx ()
    ((macro build-spec key ...)
     (with-syntax ((entry (stx-identifier #'macro 'main))
                   (origin #'(this-source-file macro))
                   ((option ...) (map (lambda (_) (genident 'option))
                                      (syntax->list #'(key ...)))))
       #'(def (entry . args)
           (let ((source origin) (option key) ...)
             (call-with-init-build-spec
               (lambda () build-spec)
               (lambda (value arguments)
                 (let ()
                   ;; The SDK macro resolves these identifiers in its calling
                   ;; context. Retain the user's source, not this adapter file.
                   (def (this-source-file) source)
                   (sdk.defbuild-script value option ...)
                   (apply main arguments)))
               args (or (pgetq libdir: (list option ...))
                        (path-expand "lib" (gerbil-path))))))))))
