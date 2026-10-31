;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
package: tao3k/yuanxu

;; POO owns the ordinary language surface. Compile-time POO construction uses
;; an explicit for-syntax import rather than duplicating its entire closure.
;; The prelude bootstraps independently of the Module System.
(import (except-in :gerbil/core object? make-object)
        :clan/poo/object
        (phi: +1 :gerbil/core)
        (phi: +2 :gerbil/core))
(export (import: :gerbil/core :clan/poo/object)
        (phi: +1 (import: :gerbil/core))
        (phi: +2 (import: :gerbil/core))
        yuanxu!)

;; Import the existing declaration syntax only when invoked. A caller-context
;; native prefix keeps init.exports hygienic without loading a second protocol.
(defsyntax (yuanxu! stx)
  (syntax-case stx ()
    ((_ clause ...)
     (let (prefix (symbol->string (gensym 'yuanxu-init-)))
       (with-syntax ((prefix-id (datum->syntax (stx-car stx) (string->symbol prefix)))
                     (entry (datum->syntax (stx-car stx)
                              (string->symbol (string-append prefix "yuanxu!"))
                              (stx-source stx))))
         #'(begin
             (import (prefix-in :yuanxu/module-system/selection/init-syntax prefix-id))
             (entry clause ...)))))))
