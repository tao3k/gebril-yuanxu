;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit clean and read-only product checks never issue artifact authority.
(import :std/test
        (only-in "../dev/gerbil/clean-outputs.ss" clean-selected-outputs!)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/make make-clean)
        (rename-in (only-in :std/build-script defbuild-script)
                   (defbuild-script gerbil-defbuild-script))
        (only-in :tao3k/yuanxu/module-system/building/products
                 build-output-directory current-build-output-directory current-build-source-directory)
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :tao3k/yuanxu/module-system/source/preparation yuanxu-prepare-module-retained-source)
        (only-in :tao3k/yuanxu/module-system/building/artifacts
                 require-build-products! test-build-publication)
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
  (test-suite "Gerbil product completion and selected marker recovery"
    (test-case "cross-package Make clean uses admitted targets without materializing source frames"
      (call-with-temporary-directory "clean-output-only"
        (lambda (root)
          (def build (path-expand "build.ss" root))
          (def libdir (path-expand "lib" root))
          (def source (path-expand "foreign/unit.ss" root))
          (write-product root "build.ss")
          (write-product root "foreign/unit.ss")
          (call-with-output-file (path-expand "gerbil.pkg" root)
            (cut display "(package: clean-consumer)\n" <>))
          (call-with-output-file (path-expand "foreign/gerbil.pkg" root)
            (cut display "(package: clean-producer)\n" <>))
          (def input (yuanxu-prepare-module-retained-source source void))
          (def entry (.o kind: 'source path: source input options: '()
                         compiler-identity: (.get input compiler-identity)))
          (def compiler-state-reads 0)
          (def graph
            (.o entries: (list entry) compiler-inputs: (.get input source-inputs)
                other-projections: '() selected-graph: #f compiler-current: void
                .source-input-state:
                (lambda (_input)
                  (set! compiler-state-reads (+ compiler-state-reads 1))
                  #f)))
          (def projection (yuanxu-project-source-spec (.o build-graph: graph) '() root build))
          (write-product libdir "clean-producer/unit.ssi")
          (write-product libdir "unrelated/unit.ssi")
          (parameterize ((current-build-output-directory libdir))
            (def entered? #f)
            (def substituted (.cc projection 'spec '("unrelated/unit")))
            (check-equal? (.get substituted spec) '("unrelated/unit"))
            (check-exception
              (.call substituted .with-clean-outputs
                (lambda () (set! entered? #t))) error?)
            (check-exception
              (.call substituted .with-compiler-inputs
                (lambda () (set! entered? #t))) error?)
            (check-equal? entered? #f)
            (check-equal? compiler-state-reads 0)
            (.call projection .with-clean-outputs
              (lambda ()
                (def directory (current-build-source-directory))
                (check-equal? (directory-files (list path: directory ignore-hidden: 'dot-and-dot-dot)) '())
                (def (this-source-file) (path-expand "build.ss" directory))
                (gerbil-defbuild-script (.get projection spec) libdir: libdir)
                (main "clean"))))
          (check-equal? (file-exists? (path-expand "clean-producer/unit.ssi" libdir)) #f)
          (check-equal? (file-exists? (path-expand "unrelated/unit.ssi" libdir)) #t)
          (check-equal? compiler-state-reads 0)
          (check-equal?
            (directory-files (list path: (path-expand ".yuanxu-source" libdir) ignore-hidden: 'dot-and-dot-dot))
            '()))))
    (test-case "clean removes only admitted package outputs and refuses changed inputs"
      (call-with-temporary-directory "clean-target-prefix"
        (lambda (root)
          (def build (path-expand "build.ss" root))
          (def libdir (path-expand "lib" root))
          (write-product root "build.ss")
          (call-with-output-file (path-expand "owned.ss" root) (cut display "(export)\n" <>))
          (call-with-output-file (path-expand "gerbil.pkg" root)
            (cut display "(package: tao3k/yuanxu prelude: :tao3k/yuanxu/prelude)\n" <>))
          (call-with-output-file (path-expand "prelude.ss" root)
            (cut display "prelude: :gerbil/core\npackage: tao3k/yuanxu\n(import :gerbil/core)\n(export (import: :gerbil/core))\n" <>))
          (def graph (.o entries: '() compiler-inputs: '()
                        other-projections: '() selected-graph: #f compiler-current: void))
          (def projection
            (yuanxu-project-source-spec (.o build-graph: graph) '("prelude" "owned") root build))
          (check-equal? (.get projection spec) '("prelude" "owned"))
          (write-product libdir "tao3k/yuanxu/prelude.ssi")
          (write-product libdir "tao3k/yuanxu/owned.ssi")
          (write-product libdir "unselected/prelude.ssi")
          (parameterize ((current-build-output-directory libdir))
            (.call projection .with-clean-outputs
              (lambda ()
                (make-clean (.get projection spec) srcdir: root libdir: libdir))))
          (check-equal? (file-exists? (path-expand "tao3k/yuanxu/prelude.ssi" libdir)) #f)
          (check-equal? (file-exists? (path-expand "tao3k/yuanxu/owned.ssi" libdir)) #f)
          (check-equal? (file-exists? (path-expand "unselected/prelude.ssi" libdir)) #t)
          (check-equal? (file-exists? (path-expand ".yuanxu-source.lock" libdir)) #t)
          (write-product libdir "tao3k/yuanxu/owned.ssi")
          (call-with-output-file (list path: (path-expand "owned.ss" root) truncate: #t)
            (cut display "(export #t)\n" <>))
          (def entered? #f)
          (parameterize ((current-build-output-directory libdir))
            (check-exception
              (.call projection .with-clean-outputs (lambda () (set! entered? #t)))
              error?))
          (check-equal? entered? #f)
          (check-equal? (file-exists? (path-expand "tao3k/yuanxu/owned.ssi" libdir)) #t))))
    (test-case "product checks and Make agree on the default and explicit output directories"
      (call-with-temporary-directory "product-output-directory"
        (lambda (root)
          (def previous (getenv "GERBIL_PATH" #f))
          (def default (path-expand "lib" root))
          (def explicit (path-expand "override" root))
          (def relative "fixture/unit.ssi")
          (dynamic-wind
            (cut setenv "GERBIL_PATH" root)
            (lambda ()
              (for-each (cut write-product <> relative) (list default explicit))
              (check-equal? (build-output-directory #f) default)
              (parameterize ((current-build-output-directory explicit))
                (check-equal? (build-output-directory) explicit))
              (make-clean '("unit") srcdir: root libdir: explicit prefix: "fixture")
              (check-equal? (file-exists? (path-expand relative explicit)) #f)
              (check-equal? (file-exists? (path-expand relative default)) #t)
              (make-clean '("unit") srcdir: root prefix: "fixture")
              (check-equal? (file-exists? (path-expand relative default)) #f))
            (cut setenv "GERBIL_PATH" previous)))))
    (test-case "explicit cleanup of an incomplete module preserves unselected products"
      (call-with-temporary-directory "product-recovery"
        (lambda (root)
          (for-each (cut write-product root <>)
            '("fixture/unit.ssi" "fixture/unit.o1" "fixture/unit.scm"
              "fixture/unit~1.scm" "static/fixture__unit.scm"
              "static/fixture__unselected.scm"))
          (check-exception (require-build-products! '(fixture/unit) root) error?)
          (clean-selected-outputs! '(fixture/unit) root)
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #f)
          (check-equal? (file-exists? (path-expand "static/fixture__unselected.scm" root)) #t)
          ;; A complete rebuild passes the read-only product check.
          (for-each (cut write-product root <>)
            '("fixture/unit.ssi" "fixture/unit.o1" "fixture/unit.scm"
              "fixture/unit~1.scm" "fixture/unit~1.o1" "static/fixture__unit.scm"))
          (require-build-products! '(fixture/unit) root)
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #t))))
    (test-case "non-regular runtime products refuse without deleting a marker"
      (call-with-temporary-directory "product-refusal"
        (lambda (root)
          (for-each (cut write-product root <>)
            '("fixture/unit.ssi" "static/fixture__unit.scm"))
          (create-directory* (path-expand "fixture/unit.o1" root))
          (check-exception (clean-selected-outputs! '(fixture/unit) root) error?)
          (check-equal? (file-exists? (path-expand "static/fixture__unit.scm" root)) #t))))
    (test-case "Gerbil directory aliases share one publication identity without crossing prefixes"
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
