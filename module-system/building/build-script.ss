;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :clan/poo/object .ref .slot?))
(export defmodule-build-script)

;; The native script still owns argument handling and Make. Bootstrap actions
;; run before reading the spec, since they may supply its compiler inputs.
(def (run-module-build args actions spec native-main)
  (def (call-action slot . inputs)
    (when (.slot? (force actions) slot)
      (apply (.ref (force actions) slot) inputs)))
  (match args
    (["meta"] (native-main '() args))
    ((or [] ["compile" . _])
     (call-action '.prepare (if (pair? args) (cdr args) '()))
     (def targets (spec))
     (def (compile) (native-main targets args))
     (if (.slot? (force actions) '.with-static-inputs)
       ((.ref (force actions) '.with-static-inputs) compile)
       (compile))
     (call-action '.finish))
    (["clean"]
     (native-main (spec) args)
     (call-action '.clean))
    (else (native-main (spec) args))))

(defsyntax (defmodule-build-script stx)
  (syntax-case stx ()
    ((ctx (native-script spec-expression keys ...) actions)
     (with-syntax ((entry (stx-identifier #'ctx 'main))
                   (native-main (stx-identifier #'native-script 'main)))
       #'(begin
           (def (entry . args)
             (def (run targets argv)
               (native-script targets keys ...)
               (apply native-main argv))
             (run-module-build args (delay actions) (lambda () spec-expression) run))
           (export entry))))))
