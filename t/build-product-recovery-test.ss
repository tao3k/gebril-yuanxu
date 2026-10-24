;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Filesystem controls only; marker repair never issues artifact authority.
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/building/artifacts
                 repair-build-products! require-build-products!))
(export build-product-recovery-test)
(def (write-product root relative)
  (def path (path-expand relative root))
  (create-directory* (path-directory path))
  (call-with-output-file path (cut display "fixture\n" <>)))
(def build-product-recovery-test
  (test-suite "SDK product completion and selected marker recovery"
    (test-case "a missing dynamic phase invalidates only its own marker"
      (call-with-temporary-directory "product-recovery"
        (lambda (root)
          (for-each (cut write-product root <>)
            '("fixture/unit.ssi" "fixture/unit.o1" "fixture/unit.scm"
              "fixture/unit~1.scm" "static/fixture__unit.scm"
              "static/fixture__unselected.scm"))
          (check-exception (require-build-products! '(fixture/unit) root) error?)
          (repair-build-products! '(fixture/unit) root)
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #f)
          (check-equal? (file-exists? (path-expand "static/fixture__unselected.scm" root)) #t)
          ;; Completed phases leave an ordinary SDK marker reusable.
          (write-product root "fixture/unit~1.o1")
          (write-product root "static/fixture__unit.scm")
          (require-build-products! '(fixture/unit) root)
          (repair-build-products! '(fixture/unit) root)
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #t))))
    (test-case "non-regular runtime products refuse without deleting a marker"
      (call-with-temporary-directory "product-refusal"
        (lambda (root)
          (for-each (cut write-product root <>)
            '("fixture/unit.ssi" "static/fixture__unit.scm"))
          (create-directory* (path-expand "fixture/unit.o1" root))
          (check-exception (repair-build-products! '(fixture/unit) root) error?)
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #t))))))
