;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Direct-source adapter refusals; no compiler invocation or source generation.
(import :std/test
        (only-in :std/source this-source-file)
        (only-in "./qualification/module-testing/fixtures.ss" selection-fixture)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :clan/poo/object .get .o .+ .cc .call)
        (only-in :gerbil/expander core-import-module module-context-path)
        (only-in :tao3k/yuanxu/module-system/building/products current-build-source-directory
                 current-build-output-directory)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :tao3k/yuanxu/module-system/source/build retained-build-entries BuildSpecContract)
        (only-in :clan/poo/mop validate)
        (only-in :tao3k/yuanxu/module-system/source/admission module-source-read call-with-module-source-callback
                 call-with-module-source-operation-measurement)
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec))
(export module-build-spec-test test-setup! test-cleanup!)
(def Fixture (selection-fixture (path-expand ".." (path-directory (this-source-file)))))
(def resource #f)
(def root #f)
(def (test-setup!)
  (set! resource (.call Fixture .acquire))
  (set! root (.get resource root)))
(def (test-cleanup!)
  (when resource
    (begin0 (.call Fixture .release resource)
      (set! resource #f) (set! root #f))))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (e)
      (if (and (Error? e) (pregexp-match pattern (Error-message e))) #t
          (begin (display-exception e) #f)))
      (lambda () (thunk) #f)))
  (def module-build-spec-test
    (test-suite "Direct source build specification identity and validity"
      (test-case "contract accounting counts actual validations even inside one caller"
        (def candidate (.o module-spec: '("module") retained-spec: '("library")
                          spec: '("module" "library")))
        (for-each
          (lambda (repetitions)
            (defvalues (_ counts)
              (call-with-module-source-operation-measurement
                (lambda ()
                  (for-each (lambda (_) (validate BuildSpecContract candidate)) repetitions))))
            (check-equal? (hash-ref counts '(calls build-spec-contract) 0)
                          (length repetitions)))
          '((once) (first second))))
      (test-case "the final spec contract denies overlapping declarations after ordinary append"
        (def (checked first second)
          (def result (append first second))
          (validate BuildSpecContract (.o module-spec: first retained-spec: second spec: result))
          result)
        (for-each
          (lambda (parts)
            (check-exception (apply checked parts) Error?))
          '((("library") ((gxc: "library")))
            (((gxc: "library")) ((exe: "library" bin: "tool")))
            (((exe: "entry" bin: "first")) ((exe: "entry" bin: "second")))
            (((gxc: "library" "-O")) ((gxc: "library" "-debug")))
            (((exe: "first" bin: "tool")) ((exe: "second" bin: "tool")))))
        (check-equal? (checked '("first") '("second")) '("first" "second")))
      (test-case "a retained executable preserves its options; duplicate sources are refused"
        (call-with-temporary-directory "build-product-boundary"
          (lambda (temporary)
            (write-source (path-expand "gerbil.pkg" temporary) "(package: build-products)\n")
            (write-source (path-expand "build.ss" temporary) "(export #t)\n")
            (write-source (path-expand "entry.ss" temporary)
              "(def (main . args) (void)) (export main)\n")
            (def graph
              (.o entries: '() compiler-inputs: '() other-projections: '()
                  selected-graph: #f compiler-current: void))
            (def (project spec)
              (yuanxu-project-source-spec (.o build-graph: graph) spec temporary
                (path-expand "build.ss" temporary)))
            (def library '(gxc: "entry" "-O"))
            (def program '(exe: "entry" bin: "entry-tool" "-debug"))
            (def selected-product (project (list program)))
            (check-equal? (.get selected-product spec) (list program))
            (check-equal? (.get selected-product compiler-identities) '(build-products/entry))
            (check-equal? (.call selected-product .admit-spec (.get selected-product spec)) (list program))
            (for-each
              (lambda (spec)
                (check-equal? (rejects? "duplicate retained compiler target" (lambda () (project spec))) #t))
              (list (list library program) (list program library) (list program program)
                    (list program '(exe: "entry" bin: "other-tool"))))
            (def source-inputs
              (retained-build-entries (list library) temporary "build-products" '()))
            (def selected-graph (.cc graph 'entries source-inputs))
            (def conflicting-products
              (yuanxu-project-source-spec (.o build-graph: selected-graph) (list program)
                temporary (path-expand "build.ss" temporary)))
            (check-exception (.call conflicting-products .admit-spec (.get conflicting-products spec)) Error?)
            (write-source (path-expand "entry.ss" temporary)
              "(def (main . args) (void)) (export main)\n;; changed\n")
            (check-exception ((.get selected-product admit-current)) Error?))))
      (test-case "retained width does not multiply Graph admission; source and Graph drift still refuse"
        (for-each
          (lambda (width)
            (call-with-temporary-directory "retained-admission-width"
              (lambda (temporary)
                (write-source (path-expand "gerbil.pkg" temporary) "(package: retained-admission)\n")
                (write-source (path-expand "build.ss" temporary) "(export #t)\n")
                (def checks 0)
                (def graph-current? #t)
                ;; Empty selected Graph protocol; ordinary retained files are
                ;; real runtime sources. This fixture never compiles or issues.
                (def graph
                  (.o entries: '() compiler-inputs: '() other-projections: '()
                      selected-graph: #f
                      .with-compiler-source-reads: (lambda (entries action) (action entries))
                      .with-compiler-source-import:
                      (lambda (_entry _input _importer _target _identity action)
                        (call-with-module-source-callback action))
                      compiler-current:
                      (lambda ()
                        (set! checks (+ checks 1))
                        (unless graph-current? (error "stale fixture Graph")))))
                (def names
                  (map (lambda (n) (string-append "owned" (number->string n))) (iota width)))
                (for-each
                  (lambda (name)
                    (write-source (path-expand (string-append name ".ss") temporary) "(export #t)\n"))
                  names)
                (def projection
                  (yuanxu-project-source-spec (.o build-graph: graph) names temporary
                    (path-expand "build.ss" temporary)))
                (check-equal? checks 1)
                (def previous checks)
                ((.get projection admit-current))
                (check-equal? (- checks previous) 1)
                (check-equal? (length (.get projection spec)) width)
                (check-equal? (.slot? projection '.make-groups) #f)
                (check-equal? (.call projection .admit-spec (.get projection spec)) (.get projection spec))
                ;; A well-shaped standard target still cannot be substituted for
                ;; the init-owned merge; structural typing alone is insufficient.
                (check-exception (.call projection .admit-spec (cons "not-selected" (.get projection spec))) Error?)
                ;; Merging the standard specs must not relocate ordinary library
                ;; inputs or give them a generated role source identity.
                ((.get projection .with-compiler-inputs)
                  (lambda ()
                    (check-equal? (current-build-source-directory) #f)
                    (check-equal?
                      (module-context-path (core-import-module (path-expand "owned0.ss" temporary)))
                      (path-normalize (path-expand "owned0.ss" temporary)))))
                ;; The parent's method is already cached. A derived receiver
                ;; cannot use it to run with a substituted final standard spec.
                (def entered? #f)
                (def substituted (.cc projection 'spec (cons "not-selected" (.get projection spec))))
                (check-exception (.call substituted .with-compiler-inputs
                                   (lambda () (set! entered? #t))) Error?)
                (check-equal? entered? #f)
                (write-source (path-expand "owned0.ss" temporary) "(export #t)\n;; changed source\n")
                (check-exception ((.get projection admit-current)) Error?)
                (write-source (path-expand "owned0.ss" temporary) "(export #t)\n")
                ((.get projection admit-current))
                (write-source (path-expand "gerbil.pkg" temporary) "(package: changed-owner)\n")
                (check-exception ((.get projection admit-current)) Error?)
                (write-source (path-expand "gerbil.pkg" temporary) "(package: retained-admission)\n")
                ((.get projection admit-current))
                (set! graph-current? #f)
                (check-exception ((.get projection admit-current)) Error?))))
          '(1 64)))
      (test-case "one selected Graph, retained overlaps, conflicts and stale entry"
        (call-with-temporary-directory "build-spec-boundaries"
          (lambda (temporary)
            (def installed-core? (file-exists? (path-expand "lib/tao3k/yuanxu" (getenv "GERBIL_PATH"))))
            (def view (yuanxu-load-modules (path-expand "init.ss" root)))
            (def selected (.get view build-graph))
            (def entry (path-expand "build.ss" root))
            (def (project roots (source-root root) (source-entry entry) (source view))
              (yuanxu-project-source-spec source roots source-root source-entry))
            ;; Use an actual selected ordinary library, not a bootstrap-tool
            ;; membership assumption that changes with the upstream closure.
            (def overlap
              (find (lambda (row)
                      (and (string-prefix? "tao3k/yuanxu/" (symbol->string (.get row compiler-identity)))
                           (string-prefix? (path-expand "modules/" root) (.get row path))))
                    (.get selected entries)))
            (unless overlap
              (error "build-spec fixture requires a selected package input"))
            (def overlap-name
              (substring (symbol->string (.get overlap compiler-identity))
                         (string-length "tao3k/yuanxu/")
                         (string-length (symbol->string (.get overlap compiler-identity)))))
            (def overlap-spec `(gxc: ,overlap-name ,@(.get overlap options)))
            (def artifact (project (list "utilities/algorithms" overlap-spec)))
            (check-equal? (eq? (.get artifact build-graph) selected) #t)
            (check-equal? (.get artifact source-root) root)
            (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
            (check-equal? (length (filter (lambda (row) (equal? (if (string? row) row (cadr row)) overlap-name))
                                        (.get artifact spec))) 1)
            (check-equal? (rejects? "conflicting retained compiler options"
                            (lambda () (project (list (append overlap-spec '("-debug")))))) #t)
            (check-equal? (rejects? "duplicate retained compiler target"
                            (lambda () (project '("types/contracts" "types/contracts")))) #t)
            (check-equal? (rejects? "retained build entries require"
                            (lambda () (project #t))) #t)
            (let (original (module-source-read entry))
              (dynamic-wind
                (lambda () (write-source entry (string-append original "\n;; changed entry\n")))
                (lambda () (check-equal? (rejects? "stale selected build input"
                                          (.get artifact admit-current)) #t))
                (lambda () (write-source entry original))))
            ((.get artifact admit-current))
            (let* ((links (path-expand "links" temporary))
                   (link (path-expand "types/contracts.ss" links))
                   (build (path-expand "build.ss" links)))
              (create-directory* (path-directory link))
              (write-source (path-expand "gerbil.pkg" links) "(package: tao3k/yuanxu)\n")
              (write-source build "(export #t)")
              (dynamic-wind
                (lambda () (create-symbolic-link (path-expand "types/contracts.ss" root) link))
                (lambda () (check-equal? (rejects? "non-regular or a symlink"
                                          (lambda () (project '("types/contracts") links build))) #t))
                (lambda () (delete-file link))))
            (let* ((foreign (path-expand "foreign" temporary))
                   (build (path-expand "build.ss" foreign)))
              (write-source (path-expand "gerbil.pkg" foreign) "(package: other)\n")
              (write-source build "(export #t)")
              (write-source (path-expand "owned.ss" foreign) "(export #t)")
              (def consumer-projection (project '("owned") foreign build))
              (check-equal? (and (member '(gxc: "other/owned") (.get consumer-projection spec)) #t) #t)
              (check-equal? (and (member 'other/owned (.get consumer-projection compiler-identities)) #t) #t)
              (for-each (lambda (entry)
                          (check-equal? (and (memq (.get entry compiler-identity)
                                             (.get consumer-projection compiler-identities)) #t) #t)
                          (check-equal? (memq (.get entry compiler-identity)
                                            (.get consumer-projection dependency-identities)) #f))
                        (.get selected entries))
              ;; A cross-package selected source view is owned by this consumer,
              ;; never by the prerequisite runtime used to execute the test.
              (parameterize ((current-build-output-directory (path-expand "lib" foreign)))
                ((.get consumer-projection .with-compiler-inputs)
                  (lambda ()
                    (check-equal? (string? (current-build-source-directory)) #t)
                    (check-equal?
                      (module-context-path (core-import-module (path-expand "owned.ss" foreign)))
                      (path-normalize (path-expand "owned.ss" foreign))))))
              (check-equal? (eq? (.get consumer-projection build-graph) selected) #t)
              ((.get consumer-projection admit-current))
              (def invoked? #f)
              (check-equal? (rejects? "requires all package owners"
                              (lambda ()
                                ((.get consumer-projection .compile) temporary
                                  (lambda () (set! invoked? #t))))) #t)
              (check-equal? invoked? #f)
              ;; A foreign dependency remains observed after target partitioning.
              (let* ((dependency (.get overlap path))
                     (original (module-source-read dependency)))
                (dynamic-wind
                  (lambda () (write-source dependency (string-append original "\n;; stale dependency\n")))
                  (lambda () (check-equal? (rejects? "stale"
                                            (.get consumer-projection admit-current)) #t))
                  (lambda () (write-source dependency original))))
              ;; Same declared compiler identity with different physical bytes is
              ;; not a deduplication opportunity.
              (set! foreign (path-expand "collision" temporary))
              (set! build (path-expand "build.ss" foreign))
              (write-source build "(export #t)")
              (write-source (path-expand "gerbil.pkg" foreign) "(package: tao3k/yuanxu)\n")
              (write-source (path-expand (string-append overlap-name ".ss") foreign)
                            (module-source-read (.get overlap path)))
              (check-equal? (rejects? "conflicting compiler inputs"
                              (lambda () (project (list overlap-spec) foreign build))) #t))
            (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" (getenv "GERBIL_PATH"))) installed-core?)))))
)
