;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :std/make make)
        (only-in :gerbil/runtime/loader load-path set-load-path! add-load-path! load-module)
        (only-in :gerbil/expander core-read-module core-import-module import-module eval-syntax module-context-path expander-context-id
                 current-expander-context current-expander-module-import make-top-context __module-pkg-cache)
        (only-in :yuanxu/module-system/building/products current-build-source-directory)
        (only-in :yuanxu/module-system/source/preparation yuanxu-write-module-publication
                 yuanxu-prepare-module-retained-source yuanxu-prepare-module-build-source
                 call-with-module-compiler-inputs module-compiler-source-input module-compiler-source-input-compatible?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-type
                 call-with-module-source-operation-measurement call-with-module-source-read-cache
                 call-with-module-source-callback current-module-source-observer)
        (only-in :yuanxu/module-system/building/configuration-source yuanxu-configuration-source))
(import (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :yuanxu/module-system/building/artifacts current-build-output-directory))
(export module-build-role-test)
(import (only-in "./qualification/module-init/fixture.ss" import-fixture-init!))
(def (assert name value)
  (unless value (error "assertion failed" name))
  (displayln "ASSERT-OK " name) (force-output))
(def (rejects? text thunk)
  (with-catch (lambda (e)
                (def message (call-with-output-string (cut display-exception e <>)))
                (def matched? (and (pregexp-match text message) #t))
                (unless matched? (display "UNEXPECTED-REJECTION ") (display message) (force-output))
                matched?)
    (lambda () (thunk) #f)))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (fixture root build)
  (let ((owner (path-expand "modules/app/example" root)))
    (write-source (path-expand "gerbil.pkg" root)
      (string-append "(package: " (symbol->string (gensym 'build-role-)) ")"))
    (write-source (path-expand "init.ss" root)
      "(yuanxu! mode: explicit source: \"./modules\" :app (example) :unused (bomb disable: #t))")
    (write-source (path-expand "types.ss" owner)
      "(import :clan/poo/object (only-in :clan/poo/mop Type.)) (def Scope (.cc Type. identity: 'scope .element?: object?)) (export Scope)")
    (write-source (path-expand "objects.ss" owner)
      "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
    (write-source (path-expand "config.ss" owner)
      "(def Config (.o value: 42))")
    (write-source (path-expand "interface.ss" owner)
      "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config forbidden: Build) projections: (list Build)) features: (.o))")
    (write-source (path-expand "build.ss" owner) build)
    (write-source (path-expand "modules/unused/bomb/interface.ss" root) "((invalid disabled interface")
    (write-source (path-expand "modules/unused/bomb/build.ss" root) "((invalid disabled build")
    (write-source (path-expand "modules/unused/unselected/interface.ss" root) "((invalid unselected interface")
    (write-source (path-expand "modules/unused/unselected/build.ss" root) "((invalid unselected build")
    owner))
(def module-build-role-test
  (test-suite "module-build-role-test"
    (yuanxu-test-case "init exports a spec List and ordinary append keeps package inputs separate"
      (call-with-temporary-directory "build-export-value"
        (lambda (root)
          (fixture root "(def Build '())")
          (write-source (path-expand "init.ss" root)
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! source: \"./modules\" mode: explicit :app (example))")
          (write-source (path-expand "support.ss" root) "(def support 42) (export support)")
          (def exports (import-fixture-init! (path-expand "init.ss" root)))
          (def started (real-time))
          (defvalues (module-spec cold-counts)
            (call-with-module-source-operation-measurement
              (lambda () (.get exports std-make-spec))))
          (def cold-seconds (- (real-time) started))
          (def hot-started (real-time))
          (defvalues (hot-spec hot-counts)
            (call-with-module-source-operation-measurement
              (lambda ()
                (for-each (lambda (_) (.get exports std-make-spec)) '(1 2 3 4 5 6 7 8 9 10))
                (.get exports std-make-spec))))
          (check-equal? (eq? module-spec hot-spec) #t)
          (check-equal? (hash-ref cold-counts '(calls build-projection) 0) 1)
          (check-equal? (hash-ref cold-counts '(calls build-spec-contract) 0) 1)
          (check-equal? (hash-ref hot-counts '(calls build-projection) 0) 0)
          (check-equal? (hash-ref hot-counts '(calls build-spec-contract) 0) 0)
          (displayln "STD-MAKE-SPEC-BENCHMARK cold-seconds=" cold-seconds
            " hot-11-seconds=" (- (real-time) hot-started)
            " cold-graph=" (hash-ref cold-counts '(calls build-projection) 0)
            " cold-contract=" (hash-ref cold-counts '(calls build-spec-contract) 0)
            " hot-graph=" (hash-ref hot-counts '(calls build-projection) 0)
            " hot-contract=" (hash-ref hot-counts '(calls build-spec-contract) 0))
          (check-equal? (list? module-spec) #t)
          (check-equal? (procedure? module-spec) #f)
          (check-equal? (eq? module-spec (.get exports std-make-spec)) #t)
          (check-equal? (.slot? exports 'library-spec) #f)
          (check-equal? (.slot? exports 'append-spec) #f)
          (def package-spec (append module-spec '("support")))
          (def support-input
            (yuanxu-prepare-module-retained-source (path-expand "support.ss" root) void))
          (check-equal? (list? package-spec) #t)
          (check-equal? (member "support" package-spec) '("support"))
          (check-equal? (member "support" module-spec) #f)
          (check-equal? (eq? module-spec (.get exports std-make-spec)) #t)
          (write-source (path-expand "support.ss" root) "(def support 43) (export support)")
          (check-exception ((.get support-input admit-current)) error?)
          ((.get exports admit-current)))))
    (yuanxu-test-case "a reached standard init reuses the same Module build evaluation"
      (call-with-temporary-directory "single-build-generation"
        (lambda (root)
          (def marker (path-expand "build-evaluations" root))
          (def owner (fixture root
            (string-append
              "(def Build (begin (call-with-output-file (list path: "
              (call-with-output-string (cut write marker <>))
              " append: #t) (lambda (port) (display \"x\" port))) '(\"client\")))")))
          ;; These authored sources are consumed by the official expander,
          ;; not a generated role wrapper or an already-installed test package.
          (write-source (path-expand "config.ss" owner)
            "(import :clan/poo/object) (def Config (.o value: 42)) (export Config)")
          (write-source (path-expand "interface.ss" owner)
            "(import (only-in :clan/poo/object .o) (only-in :yuanxu/module-system/source/declaration .def)) (.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))")
          (write-source (path-expand "init.ss" root)
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! source: \"./modules\" mode: explicit :app (example))")
          (write-source (path-expand "client.ss" owner) "(import \"../../../init.ss\") (export)")
          (def exports (import-fixture-init! (path-expand "init.ss" root)))
          (def spec (.get exports std-make-spec))
          (check-equal? (list? spec) #t)
          (check-equal? (ormap (lambda (target)
                               (equal? (if (string? target) target (cadr target)) "init")) spec) #t)
          (check-equal? (module-source-read marker) "x")
          (check-equal? (eq? spec (.get exports std-make-spec)) #t)
          (check-equal? (module-source-read marker) "x"))))
    (yuanxu-test-case "Module standard Make specs preserve library and EXE products through collection"
      (call-with-temporary-directory "module-build-make-spec"
        (lambda (root)
          (def owner (fixture root
            ;; One source can produce distinct library and executable products.
            "(def Build '((gxc: \"entry\" \"-O\") (exe: \"entry\" bin: \"entry-tool\" \"-debug\")))"))
          (write-source (path-normalize (path-expand "entry.ss" owner))
            "(def (main . args) (void)) (export main)")
          (def later (path-expand "modules/app/later" root))
          (for-each
            (lambda (role) (write-source (path-expand role later)
                            (module-source-read (path-expand role owner))))
            '("types.ss" "objects.ss" "config.ss"))
          (write-source (path-expand "library.ss" later) "(def value 42) (export value)")
          (write-source (path-expand "command.ss" later) "(def (main . args) (void)) (export main)")
          (write-source (path-expand "build.ss" later)
            "(def Build '(\"library\" (exe: \"command\" bin: \"later-tool\")))")
          (write-source (path-expand "interface.ss" later)
            "(.def Later identity: 'app/later core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))")
          (write-source (path-expand "init.ss" root)
            "(yuanxu! mode: explicit source: \"./modules\" :app (example) (later) :unused (bomb disable: #t))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def graph (.get view build-graph))
          (def rows
            (filter (lambda (row) (equal? (car row) (path-normalize (path-expand "entry.ss" owner))))
                    (.get graph std-make-targets)))
          (check-equal? (map cdr rows)
                        '((gxc: "entry" "-O") (exe: "entry" bin: "entry-tool" "-debug")))
          (check-equal? (length (filter
            (lambda (entry) (equal? (.get entry path) (path-normalize (path-expand "entry.ss" owner))))
            (.get graph entries))) 1)
          (def projection (yuanxu-project-source-spec view '() root (path-expand "init.ss" root)))
          (def targets
            (filter (lambda (target) (equal? (if (string? target) target (cadr target)) "modules/app/example/entry"))
                    (.get projection spec)))
          (check-equal? targets
            '((gxc: "modules/app/example/entry" "-O")
              (exe: "modules/app/example/entry" bin: "entry-tool" "-debug")))
          (check-equal?
            (filter (lambda (target)
                      (let (name (if (string? target) target (cadr target)))
                        (member name '("modules/app/later/library" "modules/app/later/command"))))
                    (.get projection spec))
            '("modules/app/later/library" (exe: "modules/app/later/command" bin: "later-tool")))
          (write-source (path-normalize (path-expand "entry.ss" owner))
            "(def (main . args) (void)) (export main) ;; changed")
          (check-exception ((.get projection admit-current)) error?))))
    (yuanxu-test-case "standard Module targets collect their actual imports without running sources"
      (for-each
        (lambda (program?)
          (call-with-temporary-directory "build-module-imports"
            (lambda (root)
              (def owner (fixture root
                (if program?
                  "(def Build '((exe: \"entry\" bin: \"tool\")))"
                  "(def Build '((gxc: \"entry\" \"-O\")))")))
              (write-source (path-expand "entry.ss" owner)
                "(import \"./helper.ss\") (error \"standard source must not run\") (def (main . args) answer) (export main)")
              (write-source (path-expand "helper.ss" owner)
                "(import \"./leaf.ss\") (error \"standard dependency must not run\") (def answer leaf) (export answer)")
              (write-source (path-expand "leaf.ss" owner) "(def leaf 42) (export leaf)")
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (def projection (yuanxu-project-source-spec view '() root (path-expand "init.ss" root)))
              (def targets
                (filter (lambda (target)
                          (member (if (string? target) target (cadr target))
                            '("modules/app/example/entry" "modules/app/example/helper" "modules/app/example/leaf")))
                        (.get projection spec)))
              (check-equal? (length targets) 3)
              (check-equal? (filter (lambda (target)
                                     (equal? (if (string? target) target (cadr target)) "modules/app/example/entry")) targets)
                (if program?
                  '((exe: "modules/app/example/entry" bin: "tool"))
                  '((gxc: "modules/app/example/entry" "-O"))))
              (check-equal? (ormap (lambda (target)
                                    (equal? target '(gxc: "modules/app/example/helper"))) targets) #t)
              (check-equal? (ormap (lambda (target)
                                    (equal? target '(gxc: "modules/app/example/leaf"))) targets) #t)
              (write-source (path-expand "leaf.ss" owner) "(def leaf 43) (export leaf)")
              (check-exception ((.get projection admit-current)) error?))))
        '(#f #t)))
    (yuanxu-test-case "standard Module products refuse conflicting options and binary collisions"
      (call-with-temporary-directory "module-build-programs"
        (lambda (root)
          (def owner (fixture root "(def Build '((exe: \"entry\" bin: \"entry-tool\") (exe: \"entry\" bin: \"other-tool\")))"))
          (write-source (path-expand "entry.ss" owner) "(def (main . args) (void)) (export main)")
          (def graph (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
          (def targets
            (map cdr (filter
              (lambda (row) (equal? (car row) (path-normalize (path-expand "entry.ss" owner))))
              (.get graph std-make-targets))))
          (check-equal? targets '((exe: "entry" bin: "entry-tool") (exe: "entry" bin: "other-tool")))))
      (for-each
        (lambda (control)
          (call-with-temporary-directory "module-build-conflict"
            (lambda (root)
              (def owner (fixture root (cdr control)))
              (for-each
                (lambda (name) (write-source (path-expand name owner)
                                "(def (main . args) (void)) (export main)"))
                '("entry.ss" "other.ss"))
              (check-equal? (rejects? (car control)
                (lambda () (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))) #t))))
        (list (cons "duplicate Module Make target" "(def Build '(\"entry\" \"entry\"))")
              (cons "duplicate Module Make target" "(def Build '((gxc: \"entry\" \"-O\") (gxc: \"entry\" \"-O\")))")
              (cons "duplicate Module Make target" "(def Build '((exe: \"entry\" bin: \"tool\") (exe: \"entry\" bin: \"tool\")))")
              (cons "conflicting Module Make targets" "(def Build '((gxc: \"entry\" \"-O\") (gxc: \"entry\" \"-debug\")))")
              (cons "programs share one binary output" "(def Build '((exe: \"entry\" bin: \"tool\") (exe: \"other\" bin: \"tool\")))")
              (cons "build contribution must name an owner-relative source" "(def Build '(\"../entry\"))")
              (cons "invalid Module Make target" "(def Build '((exe: \"entry\" bin: \"../tool\")))"))))
    (yuanxu-test-case "init build refuses a changed input context and cannot reuse its prepared evidence"
      (for-each
        (lambda (build)
          (call-with-temporary-directory "build-context-epoch-"
            (lambda (root)
              (fixture root build)
              (write-source (path-expand "init.ss" root)
                "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! source: \"./modules\" mode: explicit :app (example))")
              (def exports (import-fixture-init! (path-expand "init.ss" root)))
              (def before (load-path))
              ;; This fixture owns its output. The installed Core remains a
              ;; compiler prerequisite across independently checked Cases.
              (parameterize ((current-build-output-directory (path-expand "lib" root)))
                (assert 'changed-compiler-input-refused
                  (rejects? "source projection changed its compiler input context"
                    (lambda () (.get exports std-make-spec))))
                (check-equal? (load-path) before)
                (assert 'refused-input-evidence-not-reused
                  (rejects? "build input context was refused"
                    (lambda () (.get exports std-make-spec))))))))
        (list
          "(def Build (begin (set-load-path! (cons \"/invalid-build-input-context\" (load-path))) '()))"
          "(def Build (begin (set-load-path! (cons \"/invalid-build-input-context\" (load-path))) (error \"author failure after mutation\")))")))
    (yuanxu-test-case "standard preparation derives read-only eligibility from the official package cache"
      (call-with-temporary-directory "compiler-source-origin-"
        (lambda (root)
          (def path (path-expand "source.ss" root))
          (def directory (path-directory path))
          (write-source (path-expand "gerbil.pkg" root) "(package: compiler-source-origin)\n")
          (write-source path "(export value) (def value 42)\n")
          (def checker #f)
          (def bound-state #f)
          (def ready? #f)
          (def input
            (yuanxu-prepare-module-retained-source path void
              capture: (lambda (value issued source available? state)
                         (check-equal? source path)
                         (set! checker issued) (set! ready? available?) (set! bound-state state) value)))
          (check-equal? (eq? checker (.get input admit-current)) #t)
          (check-equal? (ready?) #t)
          (def cached (hash-ref __module-pkg-cache directory))
          (dynamic-wind void
            (lambda ()
              ;; Equal content is sufficient for ordinary source admission;
              ;; it is NOT the original standard cache state for a closed prefix.
              (hash-put! __module-pkg-cache directory (map values cached))
              (check-equal? (ready?) #f)
              ((.get input admit-current))
              (hash-remove! __module-pkg-cache directory)
              (check-equal? (ready?) #f)
              ((.get input admit-current))
              (check-equal? (ready?) #f))
            (lambda () (hash-put! __module-pkg-cache directory cached)))
          (check-equal? (ready?) #t)
          (def open-checker 'not-captured)
          (yuanxu-prepare-module-retained-source path (lambda () (void))
            capture: (lambda (value issued source available? state)
                       (set! open-checker issued) value))
          (check-equal? open-checker #f)
          (check-equal? (bound-state) #t)
          (def invoked 0)
          (.put! input 'admit-current (lambda () (set! invoked (+ invoked 1))))
          (check-equal? (bound-state) #f)
          (.put! input 'admit-current checker)
          (check-equal? (bound-state) #f)
          (check-equal? invoked 0))))
    (yuanxu-test-case "official cached compiler imports retain both guards and reject foreign callbacks"
      (call-with-temporary-directory "compiler-warm-import-"
        (lambda (root)
          (def owner (fixture root "(def Build '(\"source-a\"))"))
          (write-source (path-expand "source-a.ss" owner) "(def value 42) (export value)")
          (write-source (path-expand "build.ss" root) "(void)")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def graph (.get view build-graph))
          (def projection (yuanxu-project-source-spec view '() root (path-expand "build.ss" root)))
          (def entry (car (filter (lambda (entry) (eq? (.get entry kind) 'publication)) (.get graph entries))))
          (def input (.get entry input))
          (def warm-context #f)
          (parameterize ((current-build-output-directory (path-expand "lib" root))
                         (current-expander-module-import core-import-module))
            (.call projection .with-compiler-inputs
              (lambda ()
                (def path (path-expand "interface.ss" owner))
                ;; The first standard import may expand; the next two must use
                ;; its actual standard context, not a fixture-supplied warm flag.
                (def context (import-module path))
                (set! warm-context context)
                (defvalues (_reference reference)
                  (call-with-module-source-operation-measurement
                    (lambda ()
                      (for-each (lambda (_repeat)
                        ((.get input admit-current))
                        (core-import-module (module-context-path context) #f)
                        ((.get input admit-current))) '(first second)))))
                (defvalues (contexts counts)
                  (call-with-module-source-operation-measurement
                    (lambda () (list (import-module path) (import-module path)))))
                (check-equal? (andmap (lambda (next) (eq? context next)) contexts) #t)
                (check-equal? (hash-ref counts '(calls compiler-import-before) 0) 2)
                (check-equal? (hash-ref counts '(calls compiler-import-after) 0) 2)
                (check-equal? (hash-ref counts '(calls metadata-replay) 0)
                              (hash-ref reference '(calls metadata-replay) 0))
                (check-equal? (hash-ref counts '(visits metadata-replay) 0)
                              (hash-ref reference '(visits metadata-replay) 0))
                (displayln "WARM-IMPORT-PROBES reference=" (hash-ref reference '(source reads) 0)
                           " reads=" (hash-ref counts '(source reads) 0)
                           " candidates=" (hash-ref counts '(calls compiler-import-cache-hit) 0)
                           " shared=" (hash-ref counts '(calls compiler-source-shared) 0))
                (check-equal? (< (hash-ref counts '(source reads) 0)
                                (hash-ref reference '(source reads) 0)) #t)
                (check-equal? (hash-ref counts '(calls compiler-import-cache-hit) 0) 2)
                (check-equal? (hash-ref counts '(calls compiler-source-shared) 0) 2)
                (displayln "COMPILER-WARM-IMPORT reference=" (hash-ref reference '(source reads) 0) " shared=" (hash-ref counts '(source reads) 0)
                           " before=2 after=2 shared=2"))))
          ;; This source is made by Graph's standard void-context constructor,
          ;; not a Reader-derived or object-labelled purity declaration.
          (def source-entry
            (car (filter (lambda (row) (string=? (path-strip-directory (.get row path)) "source-a.ss"))
                         (.get graph entries))))
          (def source-path (.get source-entry path))
          (def source-input (.get source-entry input))
          (parameterize ((current-build-output-directory (path-expand "lib" root))
                         (current-expander-module-import core-import-module))
            (call-with-module-compiler-inputs (.get graph entries)
              (lambda ()
                ;; Exercise standard Make's enrolled descriptor. An ordinary
                ;; original-path import deliberately remains Gerbil-owned.
                (def source-target
                  (path-expand (string-append (symbol->string (.get source-entry compiler-identity)) ".ss")
                               (current-build-source-directory)))
                (def context (import-module source-target))
                (check-equal? (module-context-path context) source-path)
                (defvalues (_reference reference)
                  (call-with-module-source-operation-measurement
                    (lambda ()
                      (for-each (lambda (_repeat)
                        ((.get source-input admit-current))
                        (core-import-module (module-context-path context) #f)
                        ((.get source-input admit-current))) '(first second)))))
                (defvalues (contexts counts)
                  (call-with-module-source-operation-measurement
                    (lambda () (list (import-module source-target) (import-module source-target)))))
                (check-equal? (andmap (lambda (next) (eq? context next)) contexts) #t)
                (check-equal? (hash-ref counts '(calls compiler-import-before) 0) 2)
                (check-equal? (hash-ref counts '(calls compiler-import-after) 0) 2)
                (check-equal? (hash-ref counts '(calls compiler-source-input-shared) 0) 2)
                (check-equal? (hash-ref counts '(calls metadata-replay) 0)
                              (hash-ref reference '(calls metadata-replay) 0))
                (check-equal? (hash-ref counts '(visits metadata-replay) 0)
                              (hash-ref reference '(visits metadata-replay) 0))
                (check-equal? (< (hash-ref counts '(source reads) 0)
                                (hash-ref reference '(source reads) 0)) #t)
                (displayln "COMPILER-OWNED-INPUT reference=" (hash-ref reference '(source reads) 0)
                           " shared=" (hash-ref counts '(source reads) 0) " before=2 after=2")
                ;; Check compatibility BEFORE without-observation; suppressing
                ;; this observer to classify the path would grant false purity.
                (def observed 0)
                (defvalues (_observed observed-counts)
                  (call-with-module-source-operation-measurement
                    (lambda ()
                      (call-with-slot-read-observer (lambda (_read) (set! observed (+ observed 1)))
                        (lambda () (import-module source-target) (import-module source-target))))))
                (check-equal? (> observed 0) #t)
                (check-equal? (hash-ref observed-counts '(calls compiler-import-before) 0) 2)
                (check-equal? (hash-ref observed-counts '(calls compiler-import-after) 0) 2)
                (check-equal? (hash-ref observed-counts '(calls compiler-source-input-shared) 0) 0))
              unified?: #t source-owner: graph
              source-reads: (.get graph .with-compiler-source-reads)
              source-import: (.get graph .with-compiler-source-import)
              source-state: (.get graph .source-input-state)))
          ;; An inherited method cannot borrow the parent's compiler owner.
          (def child (.cc graph note: 'child))
          (def child-counts #f)
          (parameterize ((current-expander-module-import core-import-module))
            (call-with-module-compiler-inputs (.get graph entries)
              (lambda ()
                (def path (path-expand "interface.ss" owner))
                (import-module path)
                (let-values (((_child counts)
                              (call-with-module-source-operation-measurement
                                (lambda () (import-module path) (import-module path)))))
                  (set! child-counts counts)))
              source-owner: child source-import: (.get child .with-compiler-source-import)))
          (check-equal? (hash-ref child-counts '(calls compiler-import-before) 0) 2)
          (check-equal? (hash-ref child-counts '(calls compiler-import-after) 0) 2)
          (check-equal? (hash-ref child-counts '(calls compiler-import-cache-hit) 0) 0)
          ;; A different dynamic import procedure can mutate a source even
          ;; when it returns an already cached standard context. Keep fresh guards.
          (def callbacks 0)
          (def (foreign target reload?)
            (set! callbacks (+ callbacks 1))
            (write-source (path-expand "config.ss" owner) "(def Config (.o value: 43))")
            warm-context)
          (check-equal?
            (rejects? "stale|changed"
              (lambda ()
                (.call graph .with-compiler-source-import entry input foreign (module-context-path warm-context)
                  (expander-context-id warm-context)
                  (lambda ()
                    ((.get input admit-current))
                    (foreign (module-context-path warm-context) #f)
                    ((.get input admit-current)))))) #t)
          (check-equal? callbacks 1))))
    (yuanxu-test-case "compiler metadata closes a source suffix after the fresh publication fence"
      (call-with-temporary-directory "compiler-source-suffix-"
        (lambda (root)
          (def owner
            (fixture root
              "(def Build '(\"source-a\" \"source-b\" \"source-c\" \"source-d\"))"))
          (for-each (lambda (name)
            (write-source (path-expand (string-append name ".ss") owner)
              "(def value 42) (export value)"))
            '("source-a" "source-b" "source-c" "source-d"))
          (def graph (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
          (def entries (.get graph entries))
          (def publications (filter (lambda (entry) (eq? (.get entry kind) 'publication)) entries))
          (check-equal? (length publications) 1)
          (def fence (car publications))
          (def suffix (cdr (memq fence entries)))
          (check-equal? (>= (length suffix) 4) #t)
          ;; Mirror the compiler's existing input-index enrollment before its
          ;; inventory/view consumer: qualification cannot fill protected misses.
          (for-each (lambda (entry)
            (.get entry path) (.get entry input) (.get entry compiler-identity)
            (.get entry kind)) entries)
          (def visited '())
          (def (inspect batch)
            (for-each (lambda (entry)
              (set! visited (cons entry visited))
              ((.get entry input admit-current))) batch))
          (defvalues (_reference reference)
            (call-with-module-source-operation-measurement (lambda () (inspect entries))))
          (for-each (lambda (left right) (check-equal? (eq? left right) #t))
                    (reverse visited) entries)
          (set! visited '())
          (defvalues (_shared shared)
            (call-with-module-source-operation-measurement
              (lambda () (.call graph .with-compiler-source-reads entries inspect))))
          (check-equal? (length visited) (length entries))
          (for-each (lambda (left right) (check-equal? (eq? left right) #t))
                    (reverse visited) entries)
          (check-equal? (hash-ref shared '(calls metadata-replay) 0)
                        (hash-ref reference '(calls metadata-replay) 0))
          (check-equal? (hash-ref shared '(visits metadata-replay) 0)
                        (hash-ref reference '(visits metadata-replay) 0))
          (hash-for-each (lambda (key value)
            (when (and (pair? key) (eq? (car key) 'calls)
                       (pair? (cadr key)) (memq (caadr key) '(compiler-source-open compiler-protected-miss)))
              (write (list 'SUFFIX-OPEN key value)) (newline))) shared)
          (displayln "SUFFIX-PROBES reader=" (hash-ref shared '(calls compiler-metadata-reader) 0)
                     " inputs=" (hash-ref shared '(calls compiler-metadata-inputs) 0)
                     " fallback=" (hash-ref shared '(calls compiler-source-independent) 0))
          (check-equal? (> (hash-ref shared '(calls compiler-source-shared) 0) 0) #t)
          (check-equal? (< (hash-ref shared '(source reads) 0)
                           (hash-ref reference '(source reads) 0)) #t)
          (displayln "COMPILER-SOURCE-SUFFIX reference=" (hash-ref reference '(source reads) 0)
                     " shared=" (hash-ref shared '(source reads) 0)
                     " entries=" (length entries)))))
    (yuanxu-test-case "compiler metadata keeps the final publication fresh and every guard occurrence"
      (call-with-temporary-directory "compiler-source-prefix-"
        (lambda (root)
          (def owner (fixture root "(def Build '())"))
          (def support (path-expand "support.ss" root))
          (write-source support "(def retained-answer 42) (export retained-answer)")
          (write-source (path-expand "build.ss" root) "(void)")
          (for-each (lambda (name)
            (def next (path-expand (string-append "modules/app/" name) root))
            (for-each (lambda (role)
              (write-source (path-expand role next) (module-source-read (path-expand role owner))))
              '("types.ss" "objects.ss" "config.ss"))
            (write-source (path-expand "interface.ss" next)
              (string-append "(.def Example identity: 'app/" name
                " core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config)) features: (.o))")))
            '("second" "third"))
          (write-source (path-expand "init.ss" root)
            "(yuanxu! mode: explicit source: \"./modules\" :app (example) (second) (third))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def graph (.get view build-graph))
          (def entries (filter (lambda (entry) (eq? (.get entry kind) 'publication)) (.get graph entries)))
          (check-equal? (length entries) 3)
          ;; The compiler path index is built before the inventory/view phase.
          ;; Qualification itself must never force an unknown cold path getter.
          (for-each (lambda (entry) (.get entry path)) entries)
          (def calls 0)
          (def (inspect batch)
            (for-each (lambda (entry)
              (set! calls (+ calls 1)) ((.get entry input admit-current))) batch))
          (defvalues (_reference reference)
            (call-with-module-source-operation-measurement (lambda () (inspect entries))))
          (check-equal? calls 3)
          (set! calls 0)
          (defvalues (_shared shared)
            (call-with-module-source-operation-measurement
              (lambda () (.call graph .with-compiler-source-reads entries inspect))))
          (check-equal? calls 3)
          (check-equal? (hash-ref shared '(calls metadata-replay) 0)
                        (hash-ref reference '(calls metadata-replay) 0))
          (check-equal? (hash-ref shared '(visits metadata-replay) 0)
                        (hash-ref reference '(visits metadata-replay) 0))
          (displayln "COMPILER-SOURCE-PREFIX reference=" (hash-ref reference '(source reads) 0)
                     " shared=" (hash-ref shared '(source reads) 0)
                     " shared-windows=" (hash-ref shared '(calls compiler-source-shared) 0)
                     " fallback-windows=" (hash-ref shared '(calls compiler-source-independent) 0)
                     " reader-probes=" (hash-ref shared '(calls compiler-metadata-reader) 0)
                     " input-probes=" (hash-ref shared '(calls compiler-metadata-inputs) 0)
                     " replay-calls=" (hash-ref shared '(calls metadata-replay) 0))
          (check-equal? (< (hash-ref shared '(source reads) 0)
                           (hash-ref reference '(source reads) 0)) #t)
          ;; A derived Graph inherits the method value, not its parent's
          ;; compiler-owner authority. No claimed state callback may run here.
          (def derived-graph (.cc graph note: 'derived))
          (def claimed 0)
          (call-with-module-compiler-inputs entries
            (lambda ()
              (set! calls 0)
              (defvalues (_derived derived)
                (call-with-module-source-operation-measurement
                  (lambda () (.call derived-graph .with-compiler-source-reads entries inspect))))
              (check-equal? calls 3)
              (check-equal? (hash-ref derived '(calls compiler-source-shared) 0) 0))
            source-owner: derived-graph
            source-state: (lambda args (set! claimed (+ claimed 1)) #t))
          (check-equal? claimed 0)
          ;; Both Graph-discovered and retained-library constructors must
          ;; survive the real projection-owned compiler-input scope.
          (def projection (yuanxu-project-source-spec view '("support")
                           root (path-expand "build.ss" root)))
          (parameterize ((current-build-output-directory (path-expand "lib" root)))
            (.call projection .with-compiler-inputs
              (lambda ()
                (for-each (lambda (path)
                  (def other-checker #f)
                  (yuanxu-prepare-module-retained-source path void
                    capture: (lambda (value checker source ready? state)
                               (set! other-checker checker) value))
                  (def selected (module-compiler-source-input path))
                  (check-equal? (eq? other-checker (.get selected admit-current)) #f)
                  (check-equal? (module-compiler-source-input-compatible? path other-checker) #t)
                  (def calls-to-fake 0)
                  (def fake (.cc selected
                              source-state: (lambda args #t)
                              admit-current: (lambda () (set! calls-to-fake (+ calls-to-fake 1)))))
                  ;; Warm the counterfeit's fields: rejecting it must not rely
                  ;; on a cold getter or execute its supplied "state" procedure.
                  (.get fake compiler-identity) (.get fake admit-current)
                  (call-with-module-compiler-inputs (list (.o path input: fake))
                    (lambda ()
                      (check-equal? (module-compiler-source-input-compatible? path other-checker) #f)))
                  (check-equal? calls-to-fake 0)
                  (check-equal? (eq? selected (module-compiler-source-input path)) #t)
                  (check-equal? (module-compiler-source-input-compatible? path other-checker) #t))
                  (list (path-expand "types.ss" owner) support)))))
          (for-each
            (lambda (observe)
              (def events 0)
              (set! calls 0)
              (defvalues (_observed observed)
                (call-with-module-source-operation-measurement
                  (lambda ()
                    (observe (lambda () (set! events (+ events 1)))
                      (lambda () (.call graph .with-compiler-source-reads entries inspect))))))
              (check-equal? calls 3)
              (check-equal? (> events 0) #t)
              (check-equal? (hash-ref observed '(calls compiler-source-shared) 0) 0)
              (check-equal? (hash-ref observed '(calls compiler-source-independent) 0) 1))
            (list
              (lambda (event action)
                (parameterize ((current-module-source-observer (lambda (_key _amount) (event))))
                  (action)))
              (lambda (event action)
                (call-with-slot-read-observer (lambda (_read) (event)) action))))
          ;; A foreign entry can change metadata and even restore its value.
          ;; The next standard segment must recheck the captured revision policy.
          (def original-options (.get (car entries) options))
          (def foreign
            (.cc (car entries) input:
              (.o admit-current:
                (lambda ()
                  (.put! (car entries) 'options '(transient))
                  (.put! (car entries) 'options original-options)))))
          (set! calls 0)
          (defvalues (_foreign after-foreign)
            (call-with-module-source-operation-measurement
              (lambda () (.call graph .with-compiler-source-reads (cons foreign entries) inspect))))
          (check-equal? calls 4)
          (check-equal? (hash-ref after-foreign '(calls compiler-source-shared) 0) 0)
          (write-source (path-expand "config.ss" owner) "(def Config (.o value: 99))")
          (check-exception (.call graph .with-compiler-source-reads entries inspect) error?))))
    (yuanxu-test-case "ordinary libraries keep one canonical context behind Make input descriptors"
      (call-with-temporary-directory "canonical-library-input-"
        (lambda (root)
          (write-source (path-expand "gerbil.pkg" root) "(package: canonical-library-input)\n")
          (def source (path-expand "value.ss" root))
          (write-source source "(export value) (def value 42)\n")
          (def input (yuanxu-prepare-module-retained-source source void))
          (def original (core-import-module source))
          (def entries (list (.o path: source input options: '()
                                 compiler-identity: (.get input compiler-identity))))
          (parameterize ((current-build-output-directory (path-expand "lib" root)))
            (call-with-module-compiler-inputs entries
              (lambda ()
                (def descriptor (path-expand "canonical-library-input/value.ss"
                                  (current-build-source-directory)))
                ;; The timestamp input holds metadata only, never a source
                ;; include or another library body under a new compiler path.
                (call-with-input-file descriptor
                  (lambda (port)
                    (check-equal? (read port) 'package:)
                    (check-equal? (read port) "canonical-library-input")
                    (check-equal? (eof-object? (read port)) #t)))
                (let-values (((_prelude id _namespace _body) (core-read-module descriptor)))
                  (check-equal? id (.get input compiler-identity)))
                (def imported (import-module descriptor))
                (check-equal? (eq? imported original) #t)
                (check-equal? (module-context-path imported) (path-normalize source))
                (write-source source "(export value) (def value 5440)\n")
                ;; The original path cache being hot must not bypass the
                ;; enrolled input's byte check before returning that context.
                (check-equal? (rejects? "stale" (cut import-module descriptor)) #t)
                (write-source source "(export value) (def value 42)\n"))
              unified?: #t)))))
    (yuanxu-test-case "prepared source shares only local probes, never its owning callbacks"
      (call-with-temporary-directory "module-source-local-check"
        (lambda (root)
          (def file (path-expand "source.ss" root))
          (def package (path-expand "gerbil.pkg" root))
          (write-source package "(package: local-source-check)\n")
          (write-source file "(export value) (def value 1)\n")
          (def calls 0)
          (def change? #f)
          ;; Reference the previous unwindowed local probe order, without
          ;; substituting a fixture for the actual prepared-source guard below.
          (defvalues (_reference reference-counts)
            (call-with-module-source-operation-measurement
              (lambda ()
                (for-each (lambda (_)
                            (module-source-read file)
                            (module-source-type package)
                            (module-source-read package)) '(first second)))))
          (check-equal? (hash-get reference-counts '(source reads)) 4)
          (check-equal? (hash-get reference-counts '(source stats)) 6)
          (def input
            (yuanxu-prepare-module-retained-source file
              (lambda ()
                (set! calls (+ calls 1))
                (when change? (write-source file "(export value) (def value 2)\n")))))
          (set! calls 0)
          (defvalues (_ counts)
            (call-with-module-source-operation-measurement
              (lambda ()
                ((.get input admit-current))
                ((.get input admit-current)))))
          ;; Two independent checks read source + package twice. The package's
          ;; explicit regular-file probe and byte read share one physical stat.
          (check-equal? calls 4)
          (check-equal? (hash-get counts '(source reads)) 4)
          (check-equal? (hash-get counts '(source stats)) 4)
          (set! change? #t)
          (check-exception ((.get input admit-current)) error?)
          (check-equal? calls 5)
          (set! change? #f)
          (write-source file "(export value) (def value 1)\n")
          (write-source package "(package: changed-source-check)\n")
          (check-exception ((.get input admit-current)) error?))))
    (yuanxu-test-case "owning callbacks invalidate inherited observations, including on failure"
      (call-with-temporary-directory "prepared-source-callback-window"
        (lambda (root)
          (def file (path-expand "source.ss" root))
          (def old "(export value) (def value 1)\n")
          (def changed "(export value) (def value 2)\n")
          (write-source (path-expand "gerbil.pkg" root) "(package: callback-window)\n")
          (write-source file old)
          (def readonly (yuanxu-prepare-module-retained-source file void))
          (for-each
            (lambda (_window)
              (defvalues (_ counts)
                (call-with-module-source-operation-measurement
                  (lambda ()
                    (call-with-module-source-read-cache
                      (lambda () ((.get readonly admit-current)) ((.get readonly admit-current)))))))
              ;; Reuse within each pure window; the next window still reads
              ;; both source and package. No acceptance result is retained.
              (check-equal? (hash-get counts '(source reads)) 2))
            '(first second))
          (defvalues (_closed closed)
            (call-with-module-source-operation-measurement
              (lambda ()
                (call-with-module-source-read-cache
                  (lambda ()
                    (module-source-read file)
                    (call-with-module-source-callback (lambda () (void)))
                    ;; Opaque code may have installed an observer or guard.
                    ;; Closing the prefix must persist after its resumption.
                    (module-source-read file)
                    (module-source-read file))))))
          (check-equal? (hash-get closed '(source reads)) 3)
          (def change? #f)
          (def failure #f)
          (def original-error
            (with-catch (lambda (cause) cause) (lambda () (error "owning callback failed"))))
          (def input
            (yuanxu-prepare-module-retained-source file
              (lambda ()
                (when change? (write-source file changed))
                (when failure (raise original-error)))))
          (set! change? #t)
          (call-with-module-source-read-cache
            (lambda ()
              (check-equal? (module-source-read file) old)
              (check-equal?
                (rejects? "stale prepared build source"
                  (lambda () ((.get input admit-current)))) #t)
              (check-equal? (module-source-read file) changed)))
          (write-source file old)
          (set! failure #t)
          (call-with-module-source-read-cache
            (lambda ()
              (check-equal? (module-source-read file) old)
              (check-equal?
                (eq? (with-catch (lambda (cause) cause)
                       (lambda () ((.get input admit-current)) #f)) original-error) #t)
              (check-equal? (module-source-read file) changed))))))
    (yuanxu-test-case "compiler enrollment does not duplicate admission; every access rechecks"
      (let ((checks 0) (valid? #t))
        (def selected-path (path-expand "selected-retained.ss"))
        (def prepared-input
          (.o admit-current: (lambda ()
              (set! checks (+ checks 1))
              (unless valid? (error "selected source changed")))))
        (call-with-module-compiler-inputs (list (.o path: selected-path input: prepared-input))
          (lambda ()
            (check-equal? checks 0)
            (check-equal? (eq? (module-compiler-source-input selected-path) prepared-input) #t)
            (check-equal? checks 1)
            (check-equal? (eq? (module-compiler-source-input selected-path) prepared-input) #t)
            (check-equal? checks 2)
            (set! valid? #f)
            (check-exception (module-compiler-source-input selected-path) error?)
            (check-equal? checks 3)))
        (check-equal? (module-compiler-source-input selected-path) #f)
        (check-equal? checks 3)))
    (yuanxu-test-case "selected compiler sources survive runtime timestamp path removal only inside their owner"
      (call-with-temporary-directory "module-compiler-owned-source"
        (lambda (root)
          (def owner (fixture root "(def Build '())"))
          (def shared (path-expand "modules/shared.ss" root))
          (write-source shared "(def source-answer 42) (export source-answer)")
          (call-with-output-file (list path: (path-expand "types.ss" owner) append: #t)
            (cut display "\n(import ../../shared) (export source-answer)" <>))
          (write-source (path-expand "config.ss" owner) "(import ../../shared) (def Config (.o value: source-answer))")
          (def saved (load-path))
          (dynamic-wind
            (lambda () (add-load-path! root))
            (lambda ()
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (def scope (.get view modules app example))
              (check-equal? (.get scope config value) 42)
              (def prepared-input (yuanxu-prepare-module-retained-source shared void))
              (def entries (list (.o path: shared input: prepared-input)))
              (def without-root (filter (lambda (p) (not (equal? (path-normalize p) (path-normalize root)))) (load-path)))
              (call-with-module-compiler-inputs entries
                (lambda ()
                  (set-load-path! without-root)
                  (check-equal? (eq? (module-compiler-source-input shared) prepared-input) #t)
                  ((.get view admit-current))
                  (check-equal? (.get scope config value) 42)))
              (check-equal? (module-compiler-source-input shared) #f)
              (assert 'ambient-source-replacement-refuses-after-consumer
                (rejects? "source.*identity|source.*changed|scope.*refused"
                  (lambda () ((.get view admit-current))))))
            (lambda () (set-load-path! saved))))))
    (yuanxu-test-case "compiler association encloses source-view preparation and exception restoration"
      (call-with-temporary-directory "module-compiler-source-view-extent"
        (lambda (root)
          (def consumer (path-expand "consumer" root))
          (def provider (path-expand "provider" root))
          (def owner (fixture consumer "(def Build '())"))
          (write-source (path-expand "gerbil.pkg" provider)
            (string-append "(package: " (symbol->string (gensym 'compiler-view-provider-)) ")"))
          (def shared (path-expand "value.ss" provider))
          (write-source shared "(def source-answer 42) (export source-answer)")
          (def saved (load-path))
          (dynamic-wind
            (lambda () (add-load-path! consumer provider))
            (lambda ()
              (def original-paths (load-path))
              (def shared-input (yuanxu-prepare-module-retained-source shared void))
              (write-source (path-expand "config.ss" owner)
                (string-append "(import :" (symbol->string (.get shared-input compiler-identity))
                               ") (def Config (.o value: source-answer))"))
              (def view (yuanxu-load-modules (path-expand "init.ss" consumer)))
              (check-equal? (.get view modules app example config value) 42)
              ;; This is a real prepared role, whose owner checks an already
              ;; enrolled public library while compiler frames are prepared.
              (def interface-path (path-expand "interface.ss" owner))
              (def checking-extent? #f)
              (def interface-input
                (yuanxu-prepare-module-build-source interface-path
                  (lambda ()
                    (when (and checking-extent?
                               (not (eq? (module-compiler-source-input shared) shared-input)))
                      (error "prepared role lost its selected source association" shared))
                    (.call view admit-current))))
              (def entries
                (map (lambda (pair)
                       (def input (cdr pair))
                       (.o input path: (car pair) options: '()
                           compiler-identity: (.get input compiler-identity)))
                     (list (cons shared shared-input) (cons interface-path interface-input))))
              (def sentinel (gensym 'compiler-view-interrupted))
              (set! checking-extent? #t)
              (parameterize ((current-build-output-directory (path-expand "lib" root)))
                (check-exception
                  (call-with-module-compiler-inputs entries
                    (lambda ()
                      (check-equal? (eq? (module-compiler-source-input shared) shared-input) #t)
                      (.call view admit-current)
                      (raise sentinel))
                    unified?: #t)
                  (cut eq? <> sentinel)))
              (set! checking-extent? #f)
              (check-equal? (module-compiler-source-input shared) #f)
              (check-equal? (load-path) original-paths)
              (.call view admit-current))
            (lambda () (set-load-path! saved))))))
    (yuanxu-test-case "compiler source pin rechecks bytes and never enrolls an unselected source"
      (call-with-temporary-directory "module-compiler-source-drift"
        (lambda (root)
          (fixture root "(def Build '())")
          (def shared (path-expand "modules/shared.ss" root))
          (def foreign (path-expand "foreign/shared.ss" root))
          (write-source shared "(def value 42) (export value)")
          (def prepared-input (yuanxu-prepare-module-retained-source shared void))
          (write-source foreign (string-append "package: "
            (path-strip-trailing-directory-separator
              (path-directory (symbol->string (.get prepared-input compiler-identity))))
            "\n(error \"unselected source executed\") (def value 99) (export value)"))
          (def foreign-input (yuanxu-prepare-module-retained-source foreign void))
          (check-equal? (.get foreign-input compiler-identity) (.get prepared-input compiler-identity))
          (call-with-module-compiler-inputs (list (.o path: shared input: prepared-input))
            (lambda ()
              (check-equal? (module-compiler-source-input foreign) #f)
              (write-source shared "(def value 43) (export value)")
              (check-exception (module-compiler-source-input shared) error?)))
          (check-equal? (module-compiler-source-input shared) #f))))
    (yuanxu-test-case "public imports inherit explicit options from later selected Modules"
      (call-with-temporary-directory "module-public-library-options"
        (lambda (root)
          (def owner (fixture root
            "(def Build '(\"public\"))"))
          (def later (path-expand "modules/app/later" root))
          (for-each (lambda (role)
                      (write-source (path-expand role later)
                        (module-source-read (path-expand role owner))))
                    '("types.ss" "objects.ss" "config.ss"))
          (write-source (path-expand "helper.ss" later) "(def value 42) (export value)")
          (write-source (path-expand "build.ss" later)
            "(def Build '((gxc: \"helper\" \"-O\")))")
          (write-source (path-expand "interface.ss" later)
            "(.def Later identity: 'app/later core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))")
          (write-source (path-expand "init.ss" root)
            "(yuanxu! mode: explicit source: \"./modules\" :app (example) (later))")
          (write-source (path-expand "public.ss" owner)
            "(import \"../later/helper.ss\") (export (import: \"../later/helper.ss\"))")
          (add-load-path! root)
          (def graph (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
          (def helper (filter (lambda (entry)
                                (equal? (path-normalize (.get entry path))
                                        (path-normalize (path-expand "helper.ss" later))))
                              (.get graph entries)))
          (check-equal? (length helper) 1)
          (check-equal? (.get (car helper) options) '("-O")))))
    (yuanxu-test-case "Module public entries use the runtime import graph without runtime execution"
      (call-with-temporary-directory "module-public-library-entries"
        (lambda (root)
          (def owner (fixture root
            "(def Build '(\"public\"))"))
          (add-load-path! root)
          (write-source (path-expand "service.ss" owner)
            "(error \"public source runtime must not execute\") (def answer 42) (export answer)")
          (write-source (path-expand "public.ss" owner)
            "(import \"./service.ss\") (export (import: \"./service.ss\"))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (def graph (.get view build-graph))
          (def paths (map (cut .get <> path) (.get graph entries)))
          (assert 'public-facade-enrolled (member (path-normalize (path-expand "public.ss" owner)) (map path-normalize paths)))
          (assert 'runtime-private-dependency-enrolled (member (path-normalize (path-expand "service.ss" owner)) (map path-normalize paths)))
          (call-with-output-file (list path: (path-expand "service.ss" owner) append: #t)
            (cut display "\n;; changed actual imported source\n" <>))
          (check-exception ((.get graph compiler-current)) error?))))
    (yuanxu-test-case "standard public sources retain imports from the declared package kernel"
      (call-with-temporary-directory "module-public-library-identity"
        (lambda (root)
          (def owner (fixture root "(def Build '())"))
          (write-source (path-expand "build.ss" owner) "(def Build '(\"public\"))")
          (write-source (path-expand "kernel-helper.ss" root)
            "(error \"standard public library runtime must not execute\") (def answer 42) (export answer)")
          (write-source (path-expand "public.ss" owner)
            "(import \"../../../kernel-helper.ss\") (export (import: \"../../../kernel-helper.ss\"))")
          (add-load-path! root)
          (def graph (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
          (def paths (map (lambda (entry) (path-normalize (.get entry path))) (.get graph entries)))
          (assert 'build-public-root-enrolled (member (path-normalize (path-expand "public.ss" owner)) paths))
          (assert 'build-public-helper-enrolled (member (path-normalize (path-expand "kernel-helper.ss" root)) paths))
          (write-source (path-expand "kernel-helper.ss" root) "(def answer 43) (export answer)")
          (check-exception ((.get graph compiler-current)) error?))))
    (yuanxu-test-case "Module public entries reject package escapes and missing sources"
      (for-each
        (lambda (entry)
          (call-with-temporary-directory "module-public-library-denied"
            (lambda (root)
              (fixture root (string-append
                "(def Build '("
                (object->string entry) "))"))
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (check-exception (.get view build-graph) error?))))
        '("../escape.ss" "missing.ss" foreign/public)))
    (yuanxu-test-case "Module public entries reject symlinks, foreign identities and malformed domains"
      (for-each
        (lambda (kind)
          (call-with-temporary-directory "module-public-library-source-boundary"
            (lambda (root)
              (def owner (fixture root
                (if (eq? kind 'malformed)
                  "(def Build '(42))"
                  "(def Build '(\"public\"))")))
              (case kind
                ((foreign) (write-source (path-expand "public.ss" owner)
                             "package: other-runtime-package (def value 42) (export value)"))
                ((symlink)
                 (write-source (path-expand "target.ss" root) "(def value 42) (export value)")
                 (create-symbolic-link (path-expand "target.ss" root) (path-expand "public.ss" owner))))
              (def view (yuanxu-load-modules (path-expand "init.ss" root)))
              (check-exception (.get view build-graph) error?))))
        '(symlink foreign malformed)))
    (yuanxu-test-case "private projections preserve runtime relative-symbol imports"
      (call-with-temporary-directory "module-runtime-relative-import"
        (lambda (root)
          (def owner (fixture root "(def Build '())"))
          (add-load-path! root)
          (write-source (path-expand "shared.ss" owner) "(def answer 42) (export answer)")
          (write-source (path-expand "private/entry.ss" owner)
            "(import (only-in ../shared answer)) (export answer)")
          (write-source (path-expand "objects.ss" owner)
            "(import :clan/poo/object (only-in ./private/entry answer)) (.def Defaults value: answer) (export Defaults)")
          (write-source (path-expand "interface.ss" owner)
            "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))")
          (def view (yuanxu-load-modules (path-expand "init.ss" root)))
          (check-equal? (.get view modules app example value) 42)
          (def graph (.get view build-graph))
          (assert 'runtime-relative-import-build-graph (object? graph))
          ;; The projection must keep the actual helper in its currentness closure.
          (call-with-output-file (list path: (path-expand "shared.ss" owner) append: #t)
            (cut display "\n;; changed imported source\n" <>))
          (check-exception ((.get view admit-current)) error?))))
    (yuanxu-test-case "issued runtime compilation preserves lazy runtime roles in the Harness"
      (call-with-temporary-directory "compiled-role-demand"
        (lambda (root)
          (def marker (path-expand "config-demanded" root))
          (def owner (fixture root "(def Build '())"))
          ;; This Case concerns inert runtime roles. The existing Cases below
          ;; separately cover operational Build's declared role dependencies.
          (delete-file (path-expand "build.ss" owner))
          (write-source (path-expand "interface.ss" owner)
            "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config)) features: (.o))")
          (write-source (path-expand "build.ss" root) "(void)")
          (write-source (path-expand "types.ss" owner)
            "(import (only-in :clan/poo/mop define-type Object)) (define-type (Scope @ Object) identity: 'scope) (export Scope)")
          (write-source (path-expand "objects.ss" owner)
            "(def Defaults (error \"unused objects role initialized\")) (export Defaults)")
          (write-source (path-expand "config.ss" owner)
            (call-with-output-string
              (lambda (port)
                (write `(def Config
                          (begin (call-with-output-file (list path: ,marker append: #t) (cut display "once" <>))
                            (.o value: 42))) port))))
          (def selection (yuanxu-load-modules (path-expand "init.ss" root)))
          (def projection (yuanxu-project-source-spec selection '() root (path-expand "build.ss" root)))
          (def lib (path-expand "lib" root))
          (.call projection .compile lib
            (lambda ()
              (make (.get projection spec) srcdir: root
                libdir: (or (current-build-output-directory) lib) optimize: #f)))
          (check-equal? (file-exists? marker) #f)
          (def publication (.call selection prepare-publication 'app/example))
          (def id (symbol->string (.get publication compiler-identity)))
          (def previous (load-path))
          (dynamic-wind
            (lambda () (set-load-path! (cons lib previous)))
            (lambda ()
              (parameterize ((current-expander-context (make-top-context)))
                (eval-syntax `(import ,(path-expand (string-append id ".ssi") lib)))
                (def loaded (eval-syntax 'Example))
                (check-equal? (file-exists? marker) #f)
                (def scope (.call (.get loaded core) link (.o)))
                (check-equal? (file-exists? marker) #f)
                (def configuration (.get scope config))
                (check-equal? (.get configuration value) 42)
                (check-equal? (eq? configuration (.get scope config)) #t)
                (check-equal? (load-module id) (load-module id))
                (check-equal? (module-source-read marker) "once")
                (def file (path-expand "config.ss" owner))
                (write-source file (string-append (module-source-read file) "\n; changed after runtime load\n"))
                (check-exception (.call projection admit-current) error?)
                (check-equal? (.get configuration value) 42)))
            (lambda () (set-load-path! previous))))))
    (yuanxu-test-case "original interface compiler gets the lazy phase-bound Build binding"
      (call-with-temporary-directory "module-raw-build-binding"
        (lambda (root)
          (def marker (path-expand "build-forced" root))
          (def owner
            (fixture root
              (string-append "(def Build (begin (call-with-output-file "
                (call-with-output-string (cut write marker <>))
                " (lambda (p) (display \"wrong-phase\" p))) '()))")))
          ;; An ordinary compiler has no reader-created publication wrapper.
          ;; Explicit role imports are valid source syntax and do not import Build.
          (write-source (path-expand "config.ss" owner)
            "(import :clan/poo/object) (def Config (.o value: 42)) (export Config)")
          (write-source (path-expand "interface.ss" owner)
            "(import (except-in :clan/poo/object .def) (only-in :yuanxu/module-system/source/declaration .def)) (.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config) configuration-build: Build) features: (.o))")
          (parameterize ((current-expander-context (make-top-context)))
            (core-import-module (path-expand "interface.ss" owner)))
          (assert 'raw-compiler-binds-build-without-executing-it (not (file-exists? marker))))))
    (yuanxu-test-case "configuration cleanup does not import an unused related role"
      (call-with-temporary-directory "configuration-unused-role"
        (lambda (root)
          (def owner (fixture root "(def Build '())"))
          (write-source (path-expand "objects.ss" owner)
            "(begin-syntax (error \"unused related role expanded\")) (error \"unused related role evaluated\")")
          (write-source (path-expand "config.ss" owner)
            "(import (only-in :clan/poo/object .o)) (def Config (.o value: 42))")
          (def config
            (yuanxu-configuration-source (path-expand "config.ss" owner) 'Config void
              role-sources: (list (path-expand "objects.ss" owner))))
          (check-equal? (.get config value value) 42)
          (check-equal? (.get config value value) 42))))
    (yuanxu-test-case "Build is lazy, phase-bound and owner-scoped"
      (call-with-temporary-directory "module-build-role"
        (lambda (root)
          (let* ((marker (path-expand "build-forced" root))
                 (owner (fixture root
                   (string-append "prelude: :gerbil/core\n(def Build (begin (call-with-output-file "
                     (call-with-output-string (cut write marker <>))
                     " (lambda (p) (display \"once\" p))) '()))")))
                 (view (yuanxu-load-modules (path-expand "init.ss" root)))
                 (scope (.get view modules app example)))
            (assert 'selection-does-not-run-build (not (file-exists? marker)))
            (assert 'ordinary-scope-still-works (= (.get scope config value) 42))
            (assert 'runtime-build-denied-before-cache
              (rejects? "build-publication phase" (lambda () (.get scope forbidden))))
            (let ((prepared ((.get view prepare-publication) 'app/example))
                  (wrapper (path-expand "compiled/interface.ss" root)))
              (yuanxu-write-module-publication prepared wrapper)
              (parameterize ((current-expander-context (make-top-context)))
                (core-import-module wrapper))
              (assert 'ordinary-compiler-expansion-does-not-run-build
                (not (file-exists? marker))))
            (let (config (yuanxu-configuration-source (path-expand "config.ss" owner) 'Config void
                            role-sources: (list (path-expand "build.ss" owner))))
              (assert 'config-evaluation-excludes-build (= (.get config value value) 42)))
            (assert 'config-did-not-force-build (not (file-exists? marker)))
            (let (graph (.get view build-graph))
              (assert 'graph-access-reuses-runtime-cache (eq? graph (.get view build-graph)))
              (assert 'build-evaluated-on-graph-demand (equal? (module-source-read marker) "once"))
              (assert 'build-not-a-runtime-compiler-root
                (not (find (lambda (entry) (equal? (path-strip-directory (.get entry path)) "build.ss")) (.get graph entries))))
              (assert 'build-bytes-in-currentness
                (find (lambda (row)
                        (equal? (path-normalize (car row))
                                (path-normalize (path-expand "build.ss" owner))))
                      (.get graph source-inputs))))
            (assert 'runtime-build-denied-after-cache
              (rejects? "build-publication phase" (lambda () (.get scope forbidden))))
            (write-source (path-expand "build.ss" owner) "(def Build (error \"changed\"))")
            (assert 'build-mutation-rejects-old-generation
              (rejects? "compiler tool source changed; use a fresh reader"
                (lambda () ((.get view admit-current)))))))))
    (yuanxu-test-case "Build cannot reload root selection through an alias"
      (call-with-temporary-directory "module-build-reentry"
        (lambda (root)
          (fixture root
            (string-append
              "(import (only-in :yuanxu/module-system/interface yuanxu-load-modules)) "
              "(def reload yuanxu-load-modules) (def Build (reload "
              (call-with-output-string (cut write (path-expand "init.ss" root) <>)) "))"))
          (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
            (assert 'root-reentry-denied
              (rejects? "cannot reload the root" (lambda () (.get view build-graph))))))))
    (yuanxu-test-case "Absent Build role is observed and cannot be added to an old generation"
      (call-with-temporary-directory "module-build-absence"
        (lambda (root)
          (let (owner (fixture root "(def Build '())"))
            (delete-file (path-expand "build.ss" owner))
            (write-source (path-expand "interface.ss" owner)
              "(.def Example identity: 'app/example core: (.o requires: (.o) scope-contract: Scope exports: (.o config: Config)) features: (.o))")
            (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
              (.get view build-graph)
              (write-source (path-expand "build.ss" owner) "(def Build '())")
              (assert 'new-build-role-invalidates-old-generation
                (rejects? "stale prepared Module publication"
                (lambda () ((.get view admit-current))))))))))
    (yuanxu-test-case "Build imports cannot escape to the root init source"
      (call-with-temporary-directory "module-build-import"
        (lambda (root)
          (fixture root
            (string-append "(import "
              (call-with-output-string (cut write (path-expand "init.ss" root) <>)) ") (def Build (.o))"))
          (let (view (yuanxu-load-modules (path-expand "init.ss" root)))
            (assert 'root-init-source-import-denied
              (rejects? "admitted role|prebuilt library|owner" (lambda () (.get view build-graph))))))))))
