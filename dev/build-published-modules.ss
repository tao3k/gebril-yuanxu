;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compile the package's explicitly selected Modules before their suites.
(import (only-in :std/make make)
        (only-in :clan/poo/object .get .call)
        (only-in "../init.ss" tao3k/yuanxu.init.exports))

(def (main)
  (def projection (.get tao3k/yuanxu.init.exports build))
  (.call projection .with-compiler-inputs
    (lambda ()
      (make (.get projection spec) srcdir: (.get projection source-root)))))
