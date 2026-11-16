;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compile the package's explicitly selected Modules before their suites.
(import (only-in :std/make make)
        (only-in :clan/poo/object .get .call)
        (only-in "../init.ss" tao3k/yuanxu.init.exports))

(def (build-published-modules)
  (def projection (.get tao3k/yuanxu.init.exports build))
  (.call projection .with-compiler-inputs
    (lambda ()
      (make (.get projection std-make-spec) srcdir: (.get projection source-root)))))

(def (print-published-module-tests)
  (def tests (.get tao3k/yuanxu.init.exports tests))
  (def files (.get tests spec))
  ((.get tests admit-current))
  (unless (and (pair? files) (andmap string? files))
    (error "published Module tests must be explicit and nonempty"))
  (for-each displayln files))

(def (main (action "build"))
  (case (string->symbol action)
    ((build) (build-published-modules))
    ((tests) (print-published-module-tests))
    (else (error "unknown published Module operation" action))))
