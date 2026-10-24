;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Filesystem controls only; marker repair never issues artifact authority.
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/module-system/building/artifacts
                 repair-build-products! require-build-products! test-build-publication)
        :clan/poo/object)
(export build-product-recovery-test)
(def (write-product root relative)
  (def path (path-expand relative root))
  (create-directory* (path-directory path))
  (call-with-output-file path (cut display "fixture\n" <>)))
(def (publication-at projection prefix)
  (def previous (getenv "GERBIL_PATH" #f))
  (dynamic-wind
    (cut setenv "GERBIL_PATH" prefix)
    (cut test-build-publication projection)
    (cut setenv "GERBIL_PATH" previous)))
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
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #t))))
    (test-case "SDK directory aliases share one publication identity without crossing prefixes"
      (call-with-temporary-directory "publication-prefix"
        (lambda (root)
          (def prefix (path-expand "state" root))
          (create-directory* prefix)
          (def other-prefix (path-expand "other" root))
          (create-directory* other-prefix)
          (def projection
            (.o spec: '((gxc: "fixture/unit")) compiler-identities: '(fixture/unit)
                source-inputs: '()))
          (def canonical (publication-at projection prefix))
          (def alias (publication-at projection (string-append prefix "/../state")))
          (def other (publication-at projection other-prefix))
          (check-equal? (.get canonical artifact) (.get alias artifact))
          (check-equal? (.get canonical reference) (.get alias reference))
          (check-equal? (equal? (path-strip-directory (.get canonical artifact))
                               (path-strip-directory (.get other artifact))) #f))))))
