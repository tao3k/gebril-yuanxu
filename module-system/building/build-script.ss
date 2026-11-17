;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .call .ref .slot?)
        (only-in :std/make make make-clean)
        (only-in :tao3k/yuanxu/module-system/building/products
                 current-build-dispatch current-build-source-directory)
        (only-in :tao3k/yuanxu/module-system/source/build-binding current-module-ffi-build)
        (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path call-with-build-source-fallbacks))
(export defmodule-build-script)

;; The native script still owns argument handling and Make. Bootstrap actions
;; run before reading the spec, since they may supply its compiler inputs.
(def (build-options args)
  (foldr (lambda (arg options)
           (match arg
             ("--release" (cons* build-release: #t options))
             ("--optimized" (cons* build-optimized: #t options))
             ("--debug" (cons* debug: #t options))
             (_ (error "Unexpected build option" arg))))
         '() (if (pair? args) (cdr args) '())))

(def (run-module-build args actions spec native-main keys root)
  (def source-view #f)
  (def (project compile?)
    (def (admit-dispatch build targets)
      (when source-view (error "package build has more than one selected source view"))
      (set! source-view (cons build targets)))
    (parameterize ((current-build-dispatch admit-dispatch)
                   (current-module-ffi-build
                    (lambda (owner target)
                      (when compile?
                        (call-with-build-input-path #f
                          (lambda ()
                            (if (equal? (path-normalize owner) (path-normalize root))
                              (native-main (list target) args)
                              (apply make (list target) srcdir: owner (build-options args))))
                          make-source: owner)))))
      ;; Source guards run beyond individual module readers' extents.
      (call-with-build-source-fallbacks (list root) spec)))
  (def (dispatch targets compile?)
    (cond
      ((not source-view) (native-main targets args))
      ((not (eq? (cdr source-view) targets))
       (error "package build must consume the selected std-make-spec directly"))
      (compile?
       (.call (car source-view) .with-compiler-inputs
         (lambda ()
           (apply make targets srcdir: (current-build-source-directory)
                  (append (build-options args) (keys))))))
      (else
       (.call (car source-view) .with-clean-outputs
         (lambda ()
           (apply make-clean targets srcdir: (current-build-source-directory) (keys)))))))
  (def (call-action slot . inputs)
    (when (.slot? (force actions) slot)
      (apply (.ref (force actions) slot) inputs)))
  (match args
    (["meta"] (native-main '() args))
    ((or [] ["compile" . _])
     (call-action '.prepare (if (pair? args) (cdr args) '()))
     (def targets (project #t))
     (def (compile) (dispatch targets #t))
     (if (.slot? (force actions) '.with-static-inputs)
       ((.ref (force actions) '.with-static-inputs) compile)
       (compile))
     (call-action '.finish))
    (["clean"]
     (dispatch (project #f) #f)
     (call-action '.clean))
    (else (native-main (project #f) args))))

(defsyntax (defmodule-build-script stx)
  (syntax-case stx ()
    ((ctx (native-script spec-expression keys ...) actions)
     (with-syntax* ((entry (stx-identifier #'ctx 'main))
                    (native-main (stx-identifier #'native-script 'main))
                    (source-file (stx-identifier #'native-script 'this-source-file))
                    (origin (syntax/loc stx (source-file))))
       #'(begin
           (def (entry . args)
             (def (run targets argv)
               (native-script targets keys ...)
               (apply native-main argv))
             (run-module-build args (delay actions) (lambda () spec-expression) run
               (lambda () (list keys ...)) (path-directory origin)))
           (export entry))))))
