;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander core-import-module current-expander-context
                 make-top-context core-bind-root-syntax!)
        (only-in :tao3k/yuanxu/module-system/building/source-package module-build-source-path))
(export module-source-package-resolution-test)
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def module-source-package-resolution-test
  (test-suite "Declared package source remains authoritative over bound imports"
    (test-case "an outside binding cannot suppress standard owned-source resolution"
      (call-with-temporary-directory "package-source-resolution-"
        (lambda (root)
          (def original (path-expand "original" root))
          (def selected (path-expand "selected" root))
          (for-each (lambda (directory)
                      (write-source (path-expand "gerbil.pkg" directory)
                        "(package: source-resolution-control prelude: :gerbil/core)\n"))
                    (list original selected))
          (write-source (path-expand "value.ss" original) "(def value 1) (export value)\n")
          ;; Source lookup reads its header; it must not expand/evaluate this body.
          (write-source (path-expand "value.ss" selected) "(error \"source lookup executed application\")\n")
          (parameterize ((current-expander-context (make-top-context)))
            (def context (core-import-module (path-expand "value.ss" original)))
            (core-bind-root-syntax! ':source-resolution-control/value context #t)
            (def before (load-path))
            (check-equal? (module-build-source-path context original)
                          (path-normalize (path-expand "value.ss" original)))
            (check-equal? (module-build-source-path context selected)
                          (path-normalize (path-expand "value.ss" selected)))
            (def nested (path-expand "modules" selected))
            (write-source (path-expand "gerbil.pkg" nested)
              "(package: source-resolution-control/modules prelude: :gerbil/core)\n")
            (check-equal? (module-build-source-path context nested) #f)
            (check-equal? (module-build-source-path context selected)
                          (path-normalize (path-expand "value.ss" selected)))
            (check-equal? (load-path) before)
            (write-source (path-expand "value.ss" selected) "package: impostor\n(def value 2)\n")
            (check-exception (module-build-source-path context selected) error?)
            (check-equal? (load-path) before)))))))
