;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification-only export cut; ordinary native objects, no write wrapper.
(import :clan/poo/object)
(export .def .get object? make-private-cell private-cell-value)
;; Finality, printing opacity and private generated setters are not write barriers.
(defstruct private-cell (value) final: #t transparent: #f)
