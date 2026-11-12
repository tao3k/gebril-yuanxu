;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real compiler qualification: standard exe targets retain source authority.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-u8vector read-all-as-string)
        (only-in :std/error Error? Error-message)
        (only-in :std/os/pid getpid)
        (only-in :yuanxu/module-system/source/observations call-with-module-source-operation-measurement)
        (only-in :gerbil/expander core-import-module)
        (only-in :yuanxu/module-system/building/source-package call-with-build-input-path)
        (only-in :yuanxu/ops/progress call-with-execution-watchdog)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        "./qualification/module-init/fixture.ss")
(export module-program-test)
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
          ;; SDK make prepends srcdir. Restore fixture-owned process state before
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
      ;; Separate SDK module identities for the two in-process reference builds.
      (def package-name
        (string-append "std-build-oracle-" (number->string (length modules))
                       (if generated? "-generated" "-reference")))
      (put root "gerbil.pkg" (string-append "(package: " package-name ")\n"))
      (def entry-pids (path-expand "entry-pids" root))
      (put root "rootlib.ss" "(def base 41) (export base)")
      (put root "init.ss"
        (string-append "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! source: \"./modules\" mode: explicit "
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
            (string-append "(import (only-in :clan/poo/object .o) (only-in :yuanxu/module-system/source/declaration .def)) (.def Publication identity: '" name
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
          (put root "init.ss"
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
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
            "(import (only-in :clan/poo/object .o) (only-in :yuanxu/module-system/source/declaration .def)) (.def Example identity: 'example core: (.o requires: (.o) scope-contract: Scope exports: Config projections: (list Build)) features: (.o))")
          (put root "modules/example/command.ss"
            "(import :clan/poo/object (only-in \"../../init.ss\" module-build-program.init.exports)) (export main) (def (main . args) (displayln \"MODULE-PROGRAM-OK \" (list (.get module-build-program.init.exports modules example value) (.get module-build-program.init.exports modules example value))))")
          (call-with-output-file
            (list path: (path-expand "build.ss" root) permissions: #o755)
            (cut display
              "#!/usr/bin/env gxi\n(import (only-in :std/source this-source-file) (only-in :clan/poo/object .get) (only-in :std/build-script defbuild-script) (only-in \"./init.ss\" module-build-program.init.exports)) (defbuild-script (.get module-build-program.init.exports std-make-spec))" <>))
          ;; The same official package entry consumes the collected standard value.
          (def run (import-build-script! (path-expand "build.ss" root)))
          (run "compile")
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
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
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
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
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
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
          (def source
            (string-append
              "(import (only-in :clan/poo/object .o .get))\n"
              "(import (only-in :std/func repeat) (for-template :std/func)\n"
              " (only-in :yuanxu/module-system/source/compiled-role compiled-role-values))\n"
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
                    (only-in :yuanxu/module-system/building/products current-build-output-directory)
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
          (run "compile")
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
                        (lambda () (package-main "compile"))))))
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
