;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
package: tao3k/yuanxu

;;; Ordinary public library entry for Yuanxu declarations and deferred loading.
;;; Consumers stay on standard `:gerbil/core` (without setting a custom
;;; `prelude:` in `gerbil.pkg`) and explicitly import `:tao3k/yuanxu/lang` in
;;; the entry/declaration files that actually need Yuanxu forms.
(import "./module-system/selection/init-syntax.ss"
        (only-in "./module-system/source/autoload-declarations.ss"
                 define-yuanxu-module-declaration yuanxu-module-declaration YuanxuLibraryModule)
        (only-in "./module-system/source/module-binding.ss" module-binding-value))

(export yuanxu!
        yuanxu-module-export
        yuanxu-autoload
        yuanxu-build-autoloads
        define-yuanxu-module-declaration
        yuanxu-module-declaration
        YuanxuLibraryModule)

;; A library entry can compile to a direct call into a deferred linked module.
;; Activate it before crossing that boundary. Gerbil's loader resolves its
;; dependencies and reuses an initialized module.
(def (activate-module-bindings!)
  (load-module "tao3k/yuanxu/module-system/source/module-binding"))

(def (yuanxu-module-export specifier binding)
  (activate-module-bindings!)
  (module-binding-value specifier binding))

(def (yuanxu-autoload specifier binding contract: (contract #f))
  (def directory (current-directory))
  (def procedure
    (delay
      (parameterize ((current-directory directory))
        (let (value (if contract
                        (yuanxu-module-declaration specifier binding contract)
                        (yuanxu-module-export specifier binding)))
          (unless (procedure? value)
            (error "autoload export must be a procedure" specifier binding))
          value))))
  (lambda arguments (apply (force procedure) arguments)))
