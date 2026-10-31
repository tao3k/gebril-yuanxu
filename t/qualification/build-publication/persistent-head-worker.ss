;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "./persistent-head")
(def (main path operation . arguments)
  (def owner (persistent-head path))
  (write
    (case (string->symbol operation)
      ((inspect) (.call owner inspect))
      ((commit) (.call owner commit (car arguments)))
      (else (error "unknown selected-head worker operation" operation))))
  (newline))
