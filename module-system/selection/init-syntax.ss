;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; One Gerbil-only public binding. Semantic imports belong to the invoking module.
(import (for-syntax :gerbil/expander))
(export yuanxu!)
(defsyntax (yuanxu! stx)
  (with-syntax ((dispatch (genident 'yuanxu-declaration))
                (implementation-name (datum->syntax (stx-car stx) 'expand-yuanxu-declaration))
                (original stx))
    #'(begin
        (import (rename-in
                  (only-in :yuanxu/module-system/selection/init-expansion implementation-name)
                  (implementation-name dispatch)))
        (dispatch original))))
