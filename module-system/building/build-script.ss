;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref .slot?)
        (only-in :tao3k/yuanxu/module-system/source/build-binding current-module-ffi-build)
        (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path call-with-build-source-fallbacks))
(export defmodule-build-script)

;; The native script still owns argument handling and Make. Bootstrap actions
;; run before reading the spec, since they may supply its compiler inputs.
(def (run-module-build args actions spec native-main root)
  (def (project compile?)
    (parameterize ((current-module-ffi-build
                    (lambda (owner target)
                      (unless (equal? (path-normalize owner) (path-normalize root))
                        (error "FFI target must be built by its owning package" owner root target))
                      (when compile?
                        (call-with-build-input-path #f
                          (lambda () (native-main (list target) args))
                          make-source: root)))))
      ;; Source guards can run after a Module's local reader has returned.
      ;; The package's own source fallback must survive the whole projection.
      (call-with-build-source-fallbacks (list root) spec)))
  (def (call-action slot . inputs)
    (when (.slot? (force actions) slot)
      (apply (.ref (force actions) slot) inputs)))
  (match args
    (["meta"] (native-main '() args))
    ((or [] ["compile" . _])
     (call-action '.prepare (if (pair? args) (cdr args) '()))
     (def targets (project #t))
     (def (compile) (native-main targets args))
     (if (.slot? (force actions) '.with-static-inputs)
       ((.ref (force actions) '.with-static-inputs) compile)
       (compile))
     (call-action '.finish))
    (["clean"]
     (native-main (project #f) args)
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
               (path-directory origin)))
           (export entry))))))
