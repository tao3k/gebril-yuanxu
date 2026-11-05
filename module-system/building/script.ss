;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Preserve Gerbil syntax and dispatch; init owns selected compilation guards.
(import (prefix-in :std/build-script gerbil.)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/products current-build-source-directory current-build-compiler-options
                 current-build-module-roots)
        (only-in :yuanxu/module-system/building/interface call-with-init-build-spec))
(export defbuild-script)

;; Keep native flags in their original order. Only the wrapper owns
;; --modules; the native script must never see it.
(def (split-build-modules args)
  (let scan ((rest args) (native '()) (roots #f))
    (cond
     ((null? rest) (values (reverse native) roots))
     ((string=? (car rest) "--modules")
      (unless (and (not roots) (pair? args) (member (car args) '("compile" "spec")))
        (error "--modules may appear once after compile or spec"))
      (let names ((remaining (cdr rest)) (selected '()))
        (if (or (null? remaining) (string-prefix? "--" (car remaining)))
          (begin
            (when (null? selected) (error "--modules requires one or more module IDs"))
            (scan remaining native (reverse selected)))
          (let (id (string->symbol (car remaining)))
            (when (or (string=? (car remaining) "") (memq id selected))
              (error "empty or duplicate module ID" (car remaining)))
            (names (cdr remaining) (cons id selected))))))
     (else (scan (cdr rest) (cons (car rest) native) roots)))))

(defsyntax (defbuild-script stx)
  (syntax-case stx ()
    ((macro build-spec key ...)
     (with-syntax ((entry (stx-identifier #'macro 'main))
                   (origin #'(this-source-file macro))
                   ((option ...) (map (lambda (_) (genident 'option))
                                      (syntax->list #'(key ...)))))
       #'(def (entry . args)
           (let ((entry-source origin)
                 (option key) ...)
             (def options (list option ...))
             (defvalues (native-args roots) (split-build-modules args))
             (parameterize ((current-build-compiler-options options)
                            (current-build-module-roots roots))
              (call-with-init-build-spec
               (lambda () build-spec)
               (lambda (value arguments (package-prefix #f))
                 ;; A unified view has full compiler identities and no package
                 ;; metadata. Native std/make treats even prefix: "" as present
                 ;; and prepends a slash; it cannot name these products exactly.
                 (when (and (current-build-source-directory) (pgetq prefix: options #f))
                   (error "selected source view requires an absent Make prefix"))
                 (when (and package-prefix (memq prefix: options))
                   (error "runtime output prefix conflicts with explicit std/make prefix"
                          package-prefix (pgetq prefix: options)))
                 ;; The native macro uses the source anchor to derive srcdir.
                 ;; A selected source view changes the directory, not the entry.
                 (def (this-source-file)
                   (let (directory (current-build-source-directory))
                     (if directory
                       (path-expand (path-strip-directory entry-source) directory)
                       entry-source)))
                 (if package-prefix
                   (let ()
                     (gerbil.defbuild-script value prefix: package-prefix option ...)
                     (apply main arguments))
                   (let ()
                     (gerbil.defbuild-script value option ...)
                     (apply main arguments))))
               native-args (pgetq libdir: options) entry-source))))))))
