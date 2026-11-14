#!/usr/bin/env gxi
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; This package builds selected source owners from two package roots.
(import :std/source
        (only-in :std/make make make-clean)
        (only-in :clan/poo/object .get .call)
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :tao3k/yuanxu/module-system/building/products current-build-source-directory build-output-directory)
        (only-in "../../../../dev/gerbil/clean-outputs.ss" clean-selected-outputs!))

(def (main (operation "compile"))
  (def script (this-source-file))
  (def root (path-directory script))
  (def projection
    (yuanxu-project-source-spec (path-expand "init.ss" root) '("main") root script))
  (def spec (.get projection spec))
  (cond
    ((equal? operation "spec") (write spec) (newline))
    ((equal? operation "compile")
     (.call projection .with-compiler-inputs
       (lambda () (make spec srcdir: (current-build-source-directory)))))
    ((equal? operation "clean")
     (.call projection .with-clean-outputs
       (lambda ()
         (clean-selected-outputs! (.get projection compiler-identities) (build-output-directory)
           (lambda () (make-clean spec srcdir: (current-build-source-directory)))))))
    (else (error "unknown fixture build operation" operation))))
