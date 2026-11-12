;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real compiler qualification: standard exe targets retain source authority.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-u8vector read-all-as-string)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :std/os/pid getpid)
        (only-in :tao3k/yuanxu/module-system/source/observations call-with-module-source-operation-measurement)
        (only-in :gerbil/expander core-import-module)
        (only-in :tao3k/yuanxu/module-system/building/source-package call-with-build-input-path)
        (only-in :tao3k/yuanxu/ops/progress call-with-execution-watchdog)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint)
        (only-in :tao3k/yuanxu/ops/process-script ProcessScript.)
        (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        "./qualification/module-init/fixture.ss")
(export module-program-test build-script-options-test)
(def (put root name text)
  (def path (path-expand name root))
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (demand root)
  (.call (prepared-package-tests root) .for-files
    (list (path-expand "probe.ss" root)) '()
    '((exe: "probe" bin: "probe-test"))))
(def (with-program-workspace action)
  (call-with-temporary-directory "program-publication"
    (lambda (workspace)
      (def previous (getenv "GERBIL_PATH" #f))
      (def previous-paths (load-path))
      (def root (path-expand "source" workspace))
      (def output (path-expand "output" workspace))
      ;; Compilation and executable acceptance use the same output prefix.
      (create-directory* (path-expand "lib" output))
      (def prefix (path-normalize output))
      (dynamic-wind
        (cut setenv "GERBIL_PATH" prefix)
        (cut action root prefix)
        (lambda ()
          ;; STD Make prepends srcdir. Restore fixture-owned process state before
          ;; the temporary source directory is removed.
          (set-load-path! previous-paths)
          (setenv "GERBIL_PATH" previous))))))
(def (product-inventory prefix)
  (def (walk root relative)
    (if (not (file-exists? root)) '()
      (foldr append '()
        (map (lambda (name)
               (def path (path-expand name root))
               (def target (string-append relative name))
               (if (eq? (file-info-type (file-info path #f)) 'directory)
                 (walk path (string-append target "/"))
                 (if (or (string-suffix? ".ssi" name) (string-prefix? "bin/" target))
                   (list target) '()))) (directory-files root)))))
  (list-sort string<? (append (walk (path-expand "lib" prefix) "lib/")
                             (walk (path-expand "bin" prefix) "bin/"))))
(def (build-script-oracle modules generated?)
  (with-program-workspace
    (lambda (root prefix)
      ;; Separate Gerbil module identities for the two in-process reference builds.
      (def package-name
        (string-append "std-build-oracle-" (number->string (length modules))
                       (if generated? "-generated" "-reference")))
      (put root "gerbil.pkg" (string-append "(package: " package-name ")\n"))
      (def entry-pids (path-expand "entry-pids" root))
      (put root "rootlib.ss" "(def base 41) (export base)")
      (put root "init.ss"
        (string-append "(import :tao3k/yuanxu/module-system/selection/init-syntax) (yuanxu! source: \"./modules\" mode: explicit "
          (string-join (map (lambda (name) (string-append "(" name ")")) modules) " ")
          " (poison disable: #t))"))
      (put root "modules/poison/interface.ss" "((unselected-source-must-not-be-expanded")
      (for-each
        (lambda (name)
          (def directory (string-append "modules/" name "/"))
          (put root (string-append directory "types.ss")
            "(import :clan/poo/object (only-in :clan/poo/mop Type.)) (def Scope (.cc Type. identity: 'oracle/scope .element?: object?)) (export Scope)")
          (put root (string-append directory "objects.ss")
            "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
          (put root (string-append directory "config.ss")
            "(import :clan/poo/object) (def Config (.o)) (export Config)")
          (put root (string-append directory "helper.ss") "(def helper 1) (export helper)")
          (put root (string-append directory "library.ss")
            "(import \"./helper.ss\" \"../../rootlib.ss\") (def answer (+ helper base)) (export answer)")
          (put root (string-append directory "command.ss")
            (string-append "(import \"./library.ss\") (export main) (def (main . args) (displayln \"STD-BUILD-ORACLE " name " \" answer))"))
          (put root (string-append directory "build.ss")
            (string-append "(def Build '((exe: \"command\" bin: \"" name "-tool\")))"))
          (put root (string-append directory "interface.ss")
            (string-append "(import (only-in :clan/poo/object .o) (only-in :tao3k/yuanxu/module-system/source/declaration .def)) (.def Publication identity: '" name
              " core: (.o requires: (.o) scope-contract: Scope exports: Defaults projections: (list Build)) features: (.o))"))) modules)
      (def expected
        (append '("rootlib")
          (foldr append '()
            (map (lambda (name)
                   (append (map (lambda (file) (string-append "modules/" name "/" file))
                                '("types" "objects" "config" "interface" "helper" "library"))
                     (list `(exe: ,(string-append "modules/" name "/command") bin: ,(string-append name "-tool"))))) modules))))
      (call-with-output-file (list path: (path-expand "build.ss" root) permissions: #o755)
        (lambda (out)
          (display "#!/usr/bin/env gxi\n(import :std/build-script :std/source :std/os/pid)\n" out)
          (when generated?
            (pretty-print `(import (only-in :clan/poo/object .get)
                                  (only-in "./init.ss" ,(string->symbol (string-append package-name ".init.exports")))) out))
          (def spec-expression
            (if generated?
              `(append (.get ,(string->symbol (string-append package-name ".init.exports")) std-make-spec) '("rootlib"))
              `(quote ,expected)))
          (pretty-print
            `(defbuild-script
               (begin
                 ;; Record the process actually evaluating the official entry,
                 ;; so an interpreter-launch regression cannot pass on timing.
                 (call-with-output-file (list path: ,entry-pids append: #t)
                   (lambda (port) (write (getpid) port) (newline port)))
                 ,spec-expression)) out)))
      (def import-started (real-time))
      (def run (import-build-script! (path-expand "build.ss" root)))
      (def import-seconds (- (real-time) import-started))
      (def (read-spec)
        (call-with-input-string
          (call-with-output-string
            (lambda (out) (parameterize ((current-output-port out)) (run "spec")))) read))
      (def cold-started (real-time))
      (defvalues (spec cold-counts)
        (call-with-module-source-operation-measurement read-spec))
      (def cold-seconds (- (real-time) cold-started))
      (def hot-started (real-time))
      (defvalues (repeated-spec hot-counts)
        (call-with-module-source-operation-measurement read-spec))
      (def hot-seconds (- (real-time) hot-started))
      (check-equal? spec repeated-spec)
      (check-equal? (hash-ref cold-counts '(calls build-projection) 0) (if generated? 1 0))
      (check-equal? (hash-ref cold-counts '(calls build-spec-contract) 0) (if generated? 1 0))
      (check-equal? (hash-ref hot-counts '(calls build-projection) 0) 0)
      (check-equal? (hash-ref hot-counts '(calls build-spec-contract) 0) 0)
      (for-each
        (lambda (counts)
          (check-equal? (hash-ref counts '(calls scope-factory) 0) 0)
          (for-each
            (lambda (name)
              (check-equal?
                (hash-ref counts (list 'calls (list 'scope-factory (string->symbol name))) 0) 0))
            modules))
        (list cold-counts hot-counts))
      (displayln "STD-BUILD-ENTRY-BENCHMARK implementation=" (if generated? 'generated 'official-literal)
        " modules=" (length modules) " import-seconds=" import-seconds
        " cold-spec-seconds=" cold-seconds " hot-spec-seconds=" hot-seconds
        " cold-graph=" (hash-ref cold-counts '(calls build-projection) 0)
        " cold-contract=" (hash-ref cold-counts '(calls build-spec-contract) 0)
        " hot-graph=" (hash-ref hot-counts '(calls build-projection) 0)
        " hot-contract=" (hash-ref hot-counts '(calls build-spec-contract) 0))
      (def (normalize values)
        (list-sort string<? (map (lambda (target) (object->string (if (string? target) `(gxc: ,target) target))) values)))
      (check-equal? (normalize spec) (normalize expected))
      (run "compile")
      (def products (product-inventory prefix))
      (for-each
        (lambda (name)
          (def output (.get (.call (.cc ProcessScript.
            'command (list (path-expand (string-append "bin/" name "-tool") prefix) "-:max-heap=2G,debug=q")
            'timeout 30) .run) output))
          (check-equal? (and (string-contains output (string-append "STD-BUILD-ORACLE " name " 42")) #t) #t)) modules)
      (def hot (call-with-output-string
        (lambda (out) (parameterize ((current-output-port out)) (run "compile")))))
      (check-equal? (and (string-contains hot "... compile ") #t) #f)
      (check-equal? (product-inventory prefix) products)
      (run "clean")
      (def actual-pids (call-with-input-file entry-pids read-all))
      ;; Two spec calls, cold compile, hot compile and clean all execute in this
      ;; official test VM. Actual executable acceptance is a separate boundary.
      (check-equal? (length actual-pids) 5)
      (check-equal? (andmap (lambda (pid) (= pid (getpid))) actual-pids) #t)
      (displayln "STD-BUILD-ENTRY-PROCESSES calls=" (length actual-pids)
        " same-test-process=" (andmap (lambda (pid) (= pid (getpid))) actual-pids))
      ;; Compare the official cleanup state too. EXE's compiler metadata and
      ;; generated link stub are auxiliary files, not its declared products.
      (for-each
        (lambda (target)
          (if (string? target)
            (check-equal? (file-exists?
              (path-expand (string-append "lib/" package-name "/" target ".ssi") prefix)) #f)
            (check-equal? (file-exists?
              (path-expand (string-append "bin/" (pgetq bin: (cddr target))) prefix)) #f))) expected)
      (def (canonical-inventory paths)
        (map (lambda (path)
               (def start (string-contains path package-name))
               (if start
                 (string-append (substring path 0 start) "std-build-oracle"
                   (substring path (+ start (string-length package-name)) (string-length path)))
                 path)) paths))
      (list (canonical-inventory products)
            (canonical-inventory (product-inventory prefix))))))
;; These are authored official scripts, not a second option parser. Only the
;; STD-generated main decides whether a target or keyword is accepted.
(def (official-options-script root name spec (keys '()))
  (def path (path-expand (string-append name ".ss") root))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (out)
      (pretty-print '(import :std/source :std/build-script) out)
      (pretty-print `(defbuild-script ',spec ,@keys) out)))
  (import-build-script! path))
(def (official-options-refuse? pattern action)
  (with-catch
    (lambda (exception)
      (def message (call-with-output-string (cut display-exception exception <>)))
      (if (pregexp-match pattern message) #t
        (begin (displayln "UNEXPECTED-STD-REFUSAL " message) #f)))
    (lambda () (action) #f)))
(def (official-executable-options kind (keys '()))
  (with-program-workspace
    (lambda (root prefix)
      (put root "gerbil.pkg"
        (string-append "(package: " (symbol->string (gensym 'std-exe-options-)) ")"))
      (put root "command.ss"
        "(export main) (def (main . args) (displayln \"STD-OPTIONS-EXE-OK\"))")
      (def run (official-options-script root "build"
                  (list (list kind "command" bin: "option-tool"))
                  (append '(parallelize: 1 verbose: 9) keys)))
      (def failure
        (with-catch identity
          (lambda () (with-compiler-progress (cut run "compile")) #f)))
      (def binary (path-expand "bin/option-tool" prefix))
      (if failure
        (let (expected-static-refusal?
               (cond-expand
                 (darwin
                   ;; Forced static targets request -static on Darwin.
                   (and (memq kind '(static-exe: optimized-static-exe:))
                        (let (message (call-with-output-string (cut display-exception failure <>)))
                          (and (string-contains message "Compilation error")
                               (string-contains message "\"-static\"")))))
                 (else #f)))
          (unless expected-static-refusal?
            (displayln "UNEXPECTED-STD-EXE-FAILURE target=" kind " options=" keys)
            (raise failure))
          (check-equal? (file-exists? binary) #f)
          (displayln "STD-OPTIONS-PLATFORM-REFUSAL target=" kind " stage=static-link"))
        (let ()
          (check-equal? (file-exists? binary) #t)
          ;; Executable acceptance is separate from interpreter/build startup.
          (def result (.call (.cc ProcessScript. command: (list binary "-:max-heap=2G,debug=q") timeout: 30) .run))
          (check-equal? (.get result status) 0)
          (check-equal? (and (string-contains (.get result output) "STD-OPTIONS-EXE-OK") #t) #t)
          (run "clean")
          (check-equal? (file-exists? binary) #f))))))
(def module-program-test
  (test-suite "STD build-script conformance and program publication"
    (yuanxu-test-case "single Module spec matches an explicit official build script"
      (check-equal? (build-script-oracle '("first") #t)
                    (build-script-oracle '("first") #f)))
    (yuanxu-test-case "collected Module specs match an explicit official build script"
      (check-equal? (build-script-oracle '("first" "second") #t)
                    (build-script-oracle '("first" "second") #f)))
    (yuanxu-test-case "a Module EXE uses one standard generation and runs its cold scope without sources"
      (with-program-workspace
        (lambda (root prefix)
          (def build-marker (path-expand "build-evaluations" root))
          (def scope-marker (path-expand "scope-evaluations" prefix))
          (put root "gerbil.pkg" "(package: module-build-program)\n")
          (create-directory (path-expand "empty" root))
          (put root "init.ss"
            "(import :tao3k/yuanxu/module-system/selection/init-syntax) (yuanxu! :load-modules \"./modules\" rename: modules mode: explicit (example) :load-modules \"./empty\" rename: Empty mode: explicit)\n")
          (put root "modules/example/types.ss"
            "(import :clan/poo/object (only-in :clan/poo/mop Type.)) (def Scope (.cc Type. identity: 'program/scope .element?: object?)) (export Scope)")
          (put root "modules/example/objects.ss"
            "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
          (put root "modules/example/config.ss"
            (string-append "(import :clan/poo/object) (def Config (.o value: (begin "
              "(call-with-output-file (list path: " (object->string scope-marker)
              " append: #t) (lambda (out) (display \"x\" out))) 42))) (export Config)"))
          (put root "modules/example/build.ss"
            (string-append "(def Build (begin (call-with-output-file (list path: "
              (object->string build-marker)
              " append: #t) (lambda (out) (display \"x\" out))) '((exe: \"command\" bin: \"module-program\"))))"))
          (put root "modules/example/interface.ss"
            "(import (only-in :clan/poo/object .o) (only-in :tao3k/yuanxu/module-system/source/declaration .def)) (.def Example identity: 'example core: (.o requires: (.o) scope-contract: Scope exports: Config projections: (list Build)) features: (.o))")
          (put root "modules/example/command.ss"
            "(import :clan/poo/object (only-in \"../../init.ss\" module-build-program.init.exports)) (export main) (def (main . args) (unless (null? (.all-slots (.get module-build-program.init.exports Empty))) (error \"compiled empty namespace changed\")) (displayln \"MODULE-PROGRAM-OK \" (list (.get module-build-program.init.exports modules example value) (.get module-build-program.init.exports modules example value))))")
          (call-with-output-file
            (list path: (path-expand "build.ss" root) permissions: #o755)
            (cut display
              "#!/usr/bin/env gxi\n(import (only-in :std/source this-source-file) (only-in :clan/poo/object .get) (only-in :std/build-script defbuild-script) (only-in \"./init.ss\" module-build-program.init.exports)) (defbuild-script (.get module-build-program.init.exports std-make-spec))" <>))
          ;; The same official package entry consumes the collected standard value.
          (def run (import-build-script! (path-expand "build.ss" root)))
          (with-compiler-progress (cut run "compile"))
          (check-equal? (call-with-input-file build-marker read-all-as-string) "x")
          (check-equal? (file-exists? scope-marker) #f)
          (def binary (path-expand "bin/module-program" prefix))
          (check-equal? (file-exists? binary) #t)
          (def hidden-source (string-append root "-hidden"))
          (dynamic-wind
            (cut rename-file root hidden-source)
            (lambda ()
              (def result
                (.call (.cc ProcessScript. 'command (list binary "-:max-heap=2G,debug=q")
                            'timeout 30) .run))
              (check-equal? (.get result status) 0)
              (check-equal? (and (string-contains (.get result output) "MODULE-PROGRAM-OK (42 42)") #t) #t)
              (check-equal? (call-with-input-file scope-marker read-all-as-string) "x"))
            (cut rename-file hidden-source root))
          (check-equal? (call-with-input-file build-marker read-all-as-string) "x"))))
    (yuanxu-test-case "explicit library demand roots compile while Harness-only roots stay interpreted"
      (call-with-temporary-directory "build-library-root"
        (lambda (root)
          (put root "gerbil.pkg" "(package: build-library-fixture)\n")
          (put root "init.ss"
            "(import :tao3k/yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
          (def source "(export answer) (def answer 42)\n")
          (put root "probe.ss" source)
          (put root "unrelated.ss" "(export spare) (def spare #t)\n")
          (def tests (prepared-package-tests root))
          (def files (list (path-expand "probe.ss" root)))
          (def interpreted (.get (.call tests .for-files files) build))
          (check-equal? (.get interpreted spec) '())
          (def library
            (.get (.call tests .for-files files '()
                    '((gxc: "probe" "-O") (gxc: "unrelated"))) build))
          (check-equal? (.get library spec) '((gxc: "probe" "-O")))
          ((.get library admit-current))
          (dynamic-wind void
            (lambda ()
              (put root "probe.ss" (string-append source "; changed\n"))
              (check-exception ((.get library admit-current)) error?))
            (lambda () (put root "probe.ss" source)))
          ((.get library admit-current)))))
    (yuanxu-test-case "cached foreign source retains standard package lookup authority"
      (call-with-temporary-directory "cached-build-package"
        (lambda (root)
          (put root "gerbil.pkg" "(package: cached-build-consumer)\n")
          (put root "init.ss"
            "(import :tao3k/yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
          (def manifest "(package: cached-build-foreign)\n")
          (put root "foreign/gerbil.pkg" manifest)
          (put root "foreign/sub/helper.ss" "(export answer) (def answer 42)\n")
          (put root "support.ss"
            "(import \"./foreign/sub/helper\") (export supported-answer) (def supported-answer answer)\n")
          (put root "probe.ss"
            "(import \"./support\") (export probe) (def (probe) supported-answer)\n")
          ;; Populate Gerbil's standard registry before discovering this demand.
          ;; A reused context must retain the same package evidence as a cold one.
          (core-import-module (path-expand "foreign/sub/helper.ss" root))
          (def tests (.call (prepared-package-tests root) .for-files
                       (list (path-expand "probe.ss" root))))
          (def build (.get tests build))
          (def package-path (path-normalize (path-expand "foreign/gerbil.pkg" root)))
          (def closer (path-normalize (path-expand "foreign/sub/gerbil.pkg" root)))
          (unless (assoc package-path (.get build source-inputs))
            (display "BUILD-PACKAGE-OBSERVATION-REFUSED ")
            (write (list (.get build spec) (map car (.get build source-inputs))))
            (newline) (force-output))
          (check-equal? (cdr (assoc package-path (.get build source-inputs))) manifest)
          (check-equal? (and (assoc closer (.get build source-inputs)) #t) #t)
          (check-equal? (cdr (assoc closer (.get build source-inputs))) #f)
          ((.get build admit-current))
          (dynamic-wind void
            (lambda ()
              (put root "foreign/gerbil.pkg" "(package: substituted-build-foreign)\n")
              (check-exception ((.get build admit-current)) error?))
            (lambda () (put root "foreign/gerbil.pkg" manifest)))
          ((.get build admit-current))
          (dynamic-wind void
            (lambda ()
              (put root "foreign/sub/gerbil.pkg" "(package: nearer-build-foreign)\n")
              (check-exception ((.get build admit-current)) error?))
            (lambda () (delete-file closer)))
          ((.get build admit-current)))))
    (yuanxu-test-case "real program publication rejects stale source and altered executable"
      (with-program-workspace
        (lambda (root prefix)
          ;; This isolated temporary package is compiler Fixture data. It is
          ;; never a package boundary below the repository's test directory.
          (put root "gerbil.pkg" "(package: program-fixture)\n")
          (put root "init.ss"
            "(import :tao3k/yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
          (def source
            (string-append
              "(import (only-in :clan/poo/object .o .get))\n"
              "(import (only-in :std/func repeat) (for-template :std/func)\n"
              " (only-in :tao3k/yuanxu/module-system/source/compiled-role compiled-role-values))\n"
              "(export main) (def (main . args) "
              "(def role (compiled-role-values 'std/func '(repeat))) "
              "(displayln \"COMPILED-ROLE-OK \" ((.get role repeat) (lambda () 42) 1)) "
              "(displayln \"BUILD-PROGRAM-OK \" (.get (.o value: 42) value)))\n"))
          (put root "probe.ss" source)
          (call-with-output-file
            (list path: (path-expand "build.ss" root) permissions: #o755)
            (lambda (out)
              (display "#!/usr/bin/env -S gerbil interactive\n" out)
              (for-each (cut pretty-print <> out)
                '((import :clan/poo/object
                    (only-in :std/source this-source-file)
                    (only-in :std/build-script defbuild-script)
                    (only-in :tao3k/yuanxu/module-system/building/products current-build-output-directory)
                    (only-in "./init.ss" program-fixture.init.exports))
                  (export main)
                  (def root (path-directory (this-source-file)))
                  (defbuild-script
                    (.get (.call (.get program-fixture.init.exports tests) .for-files
                      (list (path-expand "probe.ss" root)) '()
                      '((exe: "probe" bin: "probe-test"))) std-make-spec)
                    prefix: "program-fixture"
                    libdir: (current-build-output-directory)
                    bindir: (and (current-build-output-directory)
                                 (path-expand "bin" (current-build-output-directory))))))))
          (def pending (.get (demand root) build))
          ;; The standard import graph, rather than a directory inventory, owns
          ;; the exact borrowed static inputs needed by the real executable.
          (check-equal? (pair? (.get pending static-inputs)) #t)
          ;; A reexport facade can have an empty runtime body. Mutate an
          ;; observed input byte rather than assuming the first body is nonempty.
          (def borrowed
            (car (filter (lambda (input) (positive? (string-length (.get input contents))))
                         (.get pending static-inputs))))
          (def text (.get borrowed contents))
          (def first-character (string-ref text 0))
          (dynamic-wind void
            (lambda ()
              ;; Alter only the exposed projection, never the installed input.
              ;; It must not rewrite the private expected source observation.
              (string-set! text 0 (if (char=? first-character #\X) #\Y #\X))
              (check-exception ((.get pending admit-current)) error?))
            (lambda () (string-set! text 0 first-character)))
          ((.get pending admit-current))
          (.put! borrowed 'admit-current void)
          (check-exception ((.get pending admit-current)) error?)
          (check-exception (.call pending .program 'program-fixture/probe) error?)
          (def run (import-build-script! (path-expand "build.ss" root)))
          (with-compiler-progress (cut run "compile"))
          (yuanxu-test-checkpoint 'official-program-build-completed)
          (def build (.get (demand root) build))
          ;; Standard Gerbil compile is deliberately not publication authority.
          (check-exception (.call build .program 'program-fixture/probe) error?)
          (def package-main run)
          ;; The existing POO issuer owns the effect. Invoke the SAME exported
          ;; standard entry under its output and borrowed-input scope. No new
          ;; macro, command parser or implicit publication hook is involved.
          (.call build .compile (.get build output-directory)
            (lambda ()
              (def output ((.get build compile-output)))
              (call-with-build-input-path output
                (lambda ()
                  (.call build .with-static-inputs
                    (lambda ()
                      (call-with-execution-watchdog 60000 120000
                        (lambda () (with-compiler-progress (cut package-main "compile")))))))
                make-source: root)))
          (def binary (.call build .program 'program-fixture/probe))
          (check-equal? (string-prefix? (path-expand "test-lib/" (path-normalize prefix))
                                       (path-normalize binary)) #t)
          (def result (.call (.cc ProcessScript. 'command (list binary "-:max-heap=2G,debug=q") 'timeout 30) .run))
          (check-equal? (.get result status) 0)
          (check-equal? (and (string-contains (.get result output) "BUILD-PROGRAM-OK") #t) #t)
          (check-equal? (and (string-contains (.get result output) "BUILD-PROGRAM-OK 42") #t) #t)
          (check-equal? (and (string-contains (.get result output) "COMPILED-ROLE-OK (42)") #t) #t)
          ;; Publication still requires current inputs. Execution of the already
          ;; admitted binary must not reopen the authoring package or its init.
          (def hidden-source (string-append root "-hidden"))
          (dynamic-wind
            (cut rename-file root hidden-source)
            (lambda ()
              (def deployed
                (.call (.cc ProcessScript. 'command (list binary "-:max-heap=2G,debug=q")
                            'timeout 30) .run))
              (check-equal? (.get deployed status) 0)
              (check-equal? (and (string-contains (.get deployed output) "COMPILED-ROLE-OK (42)") #t) #t))
            (cut rename-file hidden-source root))
          (check-exception (.call build .program 'program-fixture/other) error?)
          (def bytes (call-with-input-file binary read-all-as-u8vector))
          (dynamic-wind void
            (lambda ()
              (call-with-output-file (list path: binary truncate: #t) (cut display "tampered executable" <>))
              (check-exception (.call build .program 'program-fixture/probe) error?))
            (lambda ()
              (call-with-output-file (list path: binary truncate: #t)
                (lambda (out) (write-subu8vector bytes 0 (u8vector-length bytes) out)))))
          ;; Restored bytes recover only while the original source is current.
          (check-equal? (.call build .program 'program-fixture/probe) binary)
          (dynamic-wind void
            (lambda ()
              (put root "probe.ss" (string-append source "; changed source\n"))
              (check-exception (.call build .program 'program-fixture/probe) error?))
            (lambda () (put root "probe.ss" source)))
          (check-equal? (.call build .program 'program-fixture/probe) binary))))))

(def build-script-options-test
  (test-suite "Official STD build-script option behavior"
    (yuanxu-test-case "official defbuild-script accepts keyword settings and GXC plist options"
      (with-program-workspace
        (lambda (root prefix)
          (def package-name (symbol->string (gensym 'std-gxc-options-)))
          (put root "gerbil.pkg" (string-append "(package: " package-name ")"))
          (put root "library.ss"
            "(import (only-in :std/ffi C-declare)) (C-declare \"#ifndef STD_OPTIONS_PROBE\n#error missing official compiler flag\n#endif\n\") (def value 42) (export value)")
          (put root "input.txt" "first")
          (def spec '((gxc: "library" (extra-inputs: ("input.txt"))
                           "-cc-options" "-DSTD_OPTIONS_PROBE")))
          (def run (official-options-script root "build" spec
            '(optimize: #f debug: #f parallelize: 1 force: #f verbose: 0
              static: #t target: 'C build-deps: "option-build-deps"
              full-program-optimization: #f build-release: #f build-optimized: #f)))
          (check-equal? (call-with-input-string
            (call-with-output-string
              (lambda (out) (parameterize ((current-output-port out)) (run "spec")))) read) spec)
          (run "compile")
          (def product (path-expand (string-append "lib/" package-name "/library.ssi") prefix))
          (check-equal? (file-exists? product) #t)
          (def hot (call-with-output-string
            (lambda (out) (parameterize ((current-output-port out)) (run "compile")))))
          (check-equal? (and (string-contains hot "... compile ") #t) #f)
          ;; Cross the filesystem's timestamp granularity before asking Make
          ;; to observe a newer dependency; this is not a timing benchmark.
          (thread-sleep! 1.1)
          (put root "input.txt" "second")
          (def newer?
            (> (time->seconds (file-info-last-modification-time
                               (file-info (path-expand "input.txt" root))))
               (time->seconds (file-info-last-modification-time (file-info product)))))
          (check-equal? newer? #t)
          (def changed (call-with-output-string
            (lambda (out) (parameterize ((current-output-port out)) (run "compile")))))
          (check-equal? (and (string-contains changed "... compile library") #t) #t)
          (displayln "STD-EXTRA-INPUT newer=" newer?
            " recompiled=" (and (string-contains changed "... compile library") #t))
          (run "clean")
          (check-equal? (file-exists? product) #f))))
    (yuanxu-test-case "official defbuild-script builds GSC SSI copy and static include submodules"
      (with-program-workspace
        (lambda (root prefix)
          (def package-name (symbol->string (gensym 'std-submodule-options-)))
          (put root "gerbil.pkg" (string-append "(package: " package-name ")"))
          (put root "library.ss" "(def value 42) (export value)")
          (def seed (official-options-script root "seed" '("library") '(parallelize: 1)))
          (seed "compile")
          (def directory (path-expand (string-append "lib/" package-name) prefix))
          (copy-file (path-expand "library.ssi" directory) (path-expand "copied.ssi" root))
          (put root "support.scm" "(define std-options-support 42)")
          (put root "attached.scm" ";; official static include payload")
          (put root "payload.dat" "official copy payload")
          (def run (official-options-script root "build"
            '((gsc: "support") (static-include: "attached.scm")
              (copy: "payload.dat") (ssi: "copied")) '(parallelize: 1)))
          (run "compile")
          (check-equal? (file-exists? (path-expand "copied.ssi" directory)) #t)
          (check-equal? (call-with-input-file (path-expand "payload.dat" directory) read-all-as-string)
                        "official copy payload")
          (check-equal? (file-exists? (path-expand "attached.scm" directory)) #t)
          (check-equal? (file-exists? (path-expand
            (string-append "lib/static/" package-name "__support.scm") prefix)) #t)
          (run "clean")
          (check-equal? (file-exists? (path-expand "copied.ssi" directory)) #f))))
    (yuanxu-test-case "official defbuild-script builds EXE options"
      (official-executable-options exe:))
    (yuanxu-test-case "official defbuild-script builds static EXE options"
      (official-executable-options static-exe:))
    (yuanxu-test-case "official defbuild-script builds optimized EXE options"
      (official-executable-options optimized-exe:))
    (yuanxu-test-case "official defbuild-script builds optimized static EXE options"
      (official-executable-options optimized-static-exe:))
    (yuanxu-test-case "official release options use the STD platform linkage strategy"
      (official-executable-options exe: '(build-release: #t)))
    (yuanxu-test-case "official optimized release options use the STD platform linkage strategy"
      (official-executable-options exe: '(build-release: #t build-optimized: #t)))
    (yuanxu-test-case "official pkg-config options link an external library used by a real executable"
      (with-program-workspace
        (lambda (root prefix)
          (put root "gerbil.pkg"
            (string-append "(package: " (symbol->string (gensym 'std-library-options-)) ")"))
          (put root "library.ss"
            "(import (only-in :std/ffi C-declare def-C-lambda)) (C-declare \"#include <openssl/crypto.h>\") (def-C-lambda openssl-version () unsigned-long \"OpenSSL_version_num\") (export openssl-version)")
          (put root "command.ss"
            "(import \"./library.ss\") (export main) (def (main . args) (unless (> (openssl-version) 0) (error \"OpenSSL version unavailable\")) (displayln \"STD-LIBRARY-OPTIONS-OK\"))")
          ;; The declaration invokes STD helpers in the authored build script.
          ;; No copied linker flag table or dependency parser is involved.
          (def path (path-expand "build.ss" root))
          (call-with-output-file path
            (lambda (out)
              (pretty-print '(import :std/source :std/build-script
                                (only-in :std/make pkg-config-libs pkg-config-cflags)) out)
              (pretty-print
                '(defbuild-script
                   (let ((cc (pkg-config-cflags "openssl"))
                         (ld (pkg-config-libs "openssl")))
                     `((gxc: "library" "-cc-options" ,cc "-ld-options" ,ld)
                       (exe: "command" bin: "library-option-tool"
                             "-cc-options" ,cc "-ld-options" ,ld)))
                   parallelize: 1) out)))
          (def run (import-build-script! path))
          (run "compile")
          (def binary (path-expand "bin/library-option-tool" prefix))
          (check-equal? (file-exists? binary) #t)
          (def result (.call (.cc ProcessScript. command: (list binary "-:max-heap=2G,debug=q") timeout: 30) .run))
          (check-equal? (.get result status) 0)
          (check-equal? (and (string-contains (.get result output) "STD-LIBRARY-OPTIONS-OK") #t) #t)
          (run "clean")
          (check-equal? (file-exists? binary) #f))))
    (yuanxu-test-case "official defbuild-script rejects invalid options and duplicate source targets"
      (with-program-workspace
        (lambda (root _prefix)
          (put root "gerbil.pkg" "(package: std-invalid-options)")
          (put root "library.ss" "(def value 42) (export value)")
          (put root "support.scm" "(define support 42)")
          (def normal (official-options-script root "normal" '("library")))
          (check-equal? (official-options-refuse? "Unexpected"
            (lambda () (normal "compile" "--not-a-build-option"))) #t)
          (def invalid-key (official-options-script root "invalid-key" '("library")
            '(not-a-make-setting: #t)))
          (check-equal? (official-options-refuse? "[Uu]nknown keyword|[Uu]nexpected keyword"
            (lambda () (invalid-key "compile"))) #t)
          (for-each
            (lambda (control)
              (def run (official-options-script root (symbol->string (gensym 'invalid-)) (cdr control)))
              (check-equal? (official-options-refuse? (car control) (lambda () (run "compile"))) #t))
            (list
              (cons "Unrecognized spec type" '((not-a-target: "library")))
              (cons "incompatible sequence" '((gsc: "support")))
              (cons "Duplicate files in buildspec" '("library" (gxc: "library")))
              (cons "Duplicate files in buildspec" '("library" (exe: "library" bin: "tool")))
              (cons "Duplicate files in buildspec"
                '((exe: "library" bin: "first") (exe: "library" bin: "second"))))))))
    ))
