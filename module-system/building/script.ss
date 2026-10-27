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
     (with-syntax* ((entry (stx-identifier #'macro 'main))
                   (origin #'(this-source-file macro))
                   ((option ...) (map (lambda (_) (genident 'option))
                                      (syntax->list #'(key ...))))
                   ((sdk-option ...)
                    (let loop ((keys (syntax->list #'(key ...)))
                               (bindings (syntax->list #'(option ...))))
                      (cond ((null? keys) '())
                            ((eq? (stx-e (car keys)) libdir:)
                             (loop (cddr keys) (cddr bindings)))
                            (else (cons (car bindings) (loop (cdr keys) (cdr bindings))))))))
       #'(def (entry . args)
           (let ((source origin) (option key) ...)
             (def options (list option ...))
             (call-with-init-build-spec
               (lambda () build-spec)
               (lambda (value arguments (native-prefix #f) (native-libdir #f))
                 (when (and native-prefix (memq prefix: options))
                   (error "native output prefix conflicts with explicit SDK prefix"
                          native-prefix (pgetq prefix: options)))
                 (if native-prefix
                   (let ()
                     (def (this-source-file) source)
                     (sdk.defbuild-script value prefix: native-prefix
                       libdir: (or native-libdir (pgetq libdir: options)
                                   (path-expand "lib" (gerbil-path))) sdk-option ...)
                     (apply main arguments))
                   (let ()
                     ;; Preserve the SDK macro's source binding at the caller.
                     (def (this-source-file) source)
                     (sdk.defbuild-script value
                       libdir: (or native-libdir (pgetq libdir: options)
                                   (path-expand "lib" (gerbil-path))) sdk-option ...)
                     (apply main arguments))))
               args (or (pgetq libdir: options)
                        (path-expand "lib" (gerbil-path))))))))))
