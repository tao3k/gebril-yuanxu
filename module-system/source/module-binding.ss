;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Resolve a public Gerbil binding when its owner is actually demanded.
(import (only-in :gerbil/expander core-import-module core-module->prelude-context
                 make-top-context current-expander-context core-expand import-module eval-syntax
                 module-context-export module-export-name))
(export module-binding-action)

(def (module-binding-action module binding)
  (def specifier (string->symbol (string-append ":" module)))
  (lambda (arguments)
    ;; Use Gerbil's shared weak language frame. Resolve on every call so a
    ;; reload cannot retain the previous procedure or its import authority.
    (let* ((language (core-import-module ':gerbil/core))
           (collision? (ormap (lambda (entry) (eq? binding (module-export-name entry)))
                              (module-context-export language))))
      (parameterize ((current-expander-context
                      (make-top-context (and (not collision?)
                                          (core-module->prelude-context language)))))
        ;; A colliding binding must still follow strong-import rules. Keep
        ;; the caller's import hook so cached imports retain their provenance.
        (when collision? (core-expand '(import :gerbil/core)))
        (core-expand `(import (only-in ,specifier ,binding)))
        (import-module specifier #f #t)
        (apply (eval-syntax binding) arguments)))))
