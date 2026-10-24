;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-only import of a freshly generated package through its real identity.
(import (only-in :gerbil/expander core-read-module/sexp eval-syntax)
        (only-in :yuanxu/module-system/source/init module-init-export-name))
(export import-fixture-init!)
(def (import-fixture-init! path)
  ;; A fresh top context has no import transformers until its prelude is bound.
  (eval-syntax '(import :gerbil/core))
  (let-values (((_prelude identity _namespace _body) (core-read-module/sexp path)))
    (let (binding (module-init-export-name identity))
      (eval-syntax
        `(import (rename-in (only-in ,path ,binding) (,binding FixtureExports))))
      (eval-syntax 'FixtureExports))))
