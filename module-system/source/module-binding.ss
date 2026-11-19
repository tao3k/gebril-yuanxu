;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Resolve a public Gerbil binding when its owner is actually demanded.
(import (only-in :gerbil/expander core-import-module core-module->prelude-context
                 make-top-context current-expander-context core-expand import-module eval-syntax
                 module-context-export module-export-name)
        (only-in :gerbil/runtime/init gerbil-load-expander!))
(export module-binding-action module-binding-value module-binding-autoload)

(def (call-with-module-binding specifier binding consume)
  (let* ((language (core-import-module ':gerbil/core))
         (collision? (ormap (lambda (entry) (eq? binding (module-export-name entry)))
                            (module-context-export language))))
    (parameterize ((current-expander-context
                    (make-top-context (and (not collision?)
                                        (core-module->prelude-context language)))))
      ;; Keep strong-import rules for collisions and preserve the caller's
      ;; import hook and its provenance checks.
      (when collision? (core-expand '(import :gerbil/core)))
      (core-expand `(import (only-in ,specifier ,binding)))
      (import-module specifier #f #t)
      (consume (eval-syntax binding)))))

(def (module-binding-action module binding)
  (def specifier (string->symbol (string-append ":" module)))
  ;; Resolve for every call so factories observe reload and import authority.
  (lambda (arguments)
    (call-with-module-binding specifier binding (cut apply <> arguments))))

(def (module-binding-value specifier binding)
  (gerbil-load-expander!)
  (call-with-module-binding specifier binding values))

(def (module-binding-autoload specifier binding)
  (def directory (current-directory))
  ;; The owner may publish a callback long before its code is needed. Gerbil
  ;; still owns module initialization and the module registry.
  (def procedure
    (delay
      (parameterize ((current-directory directory))
        (let (value (module-binding-value specifier binding))
          (unless (procedure? value)
            (error "autoload export must be a procedure" specifier binding))
          value))))
  (lambda arguments (apply (force procedure) arguments)))
