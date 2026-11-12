;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test metadata and support specification; standard build qualification owns compilation.
(import "./qualification/module-init/fixture.ss" :std/test :clan/poo/object
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :gerbil/runtime/loader list-modules)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in "./qualification/testing/directory.ss" DirectoryFixture write-source))
(export module-test-preparation-test)
(def (forms root name body)
  (write-source (path-expand name root)
    (call-with-output-string (lambda (out) (for-each (cut pretty-print <> out) body)))))
(.def (TestPackage @ DirectoryFixture)
  .prepare:
  (lambda (workspace)
    (def root (.get workspace root))
    (def package-name (string->symbol (symbol->string (gensym 'test-package-))))
    (forms root "gerbil.pkg" `((package: ,package-name)))
    (forms root "init.ss"
      '((import :yuanxu/module-system/selection/init-syntax)
        (yuanxu! mode: explicit source: "./modules" (example))))
    (forms root "modules/example/types.ss"
      '((import :clan/poo/object (only-in :clan/poo/mop Type.))
        (def Scope (.cc Type. identity: 'test/scope .element?: object?))
        (export Scope)))
    (forms root "modules/example/config.ss" '((def Config (.o enabled: #t))))
    (forms root "modules/example/objects.ss" '((def Defaults #t) (export Defaults)))
    (forms root "modules/example/interface.ss"
      '((.def Example identity: 'example features: (.o)
          core: (.o requires: (.o) scope-contract: Scope
                    exports: (error "test discovery evaluated business scope")))))
    (forms root "modules/poison/interface.ss" '((error "unselected module demanded")))
    (forms root "modules/example/tests/shared.ss" '((export answer) (def answer 42)))
    (forms root "modules/example/tests/atomic-test.ss"
      `((import :std/test "./shared.ss") (export atomic-test)
        (call-with-output-file ,(path-expand "harness-started" root)
          (lambda (out) (display "runtime Harness import" out)))
        (def atomic-test (test-suite "prepared runtime support"
          (test-case "compiled helper"
            (check-equal? answer 42)
            (call-with-output-file ,(path-expand "case-finished" root)
              (lambda (out) (display "runtime TestCase executed" out))))))))
    workspace))
(def (exports-at root)
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (import-fixture-init! (path-expand "init.ss" root))))
;; Observe the Gerbil loader itself; do not substitute a hand-maintained module
;; table. The nonempty support Case below is the positive matcher control.
(def (artifact-runtime-loaded?)
  (ormap (lambda (entry)
           (string-prefix? "yuanxu/module-system/building/artifacts" (car entry)))
         (list-modules)))
(def module-test-preparation-test
  (test-suite "Init-owned test inputs and standard Make support"
    (yuanxu-test-fixture "support-free projection neither loads business roles nor an issuer"
      (workspace TestPackage)
      (def root (.get workspace root))
      (forms root "modules/example/types.ss" '((error "business Types were demanded")))
      (forms root "modules/example/tests/plain-test.ss"
        '((import :std/test) (export plain-test)
          (def plain-test (test-suite "plain" (test-case "standard" (check-equal? 1 1))))))
      (def exports (exports-at root))
      (def tests (.call (.get exports tests) .for-files
        (list (path-expand "modules/example/tests/plain-test.ss" root))))
      (check-equal? (.get tests std-make-spec) '())
      (check-equal? (artifact-runtime-loaded?) #f)
      (check-equal? (.ref/cached tests 'selected-graph) #f)
      (for-each (lambda (name) (check-equal? (.slot? tests name) #f))
                '(.run .compile execution))
      ((.get tests admit-current))
      (forms root "init.ss" '((error "changed init")))
      (check-exception ((.get tests admit-current)) error?))
    (yuanxu-test-fixture "standard spec binds shared inputs without compiling or running a Suite"
      (workspace TestPackage)
      (def root (.get workspace root))
      (def exports (exports-at root))
      (def tests (.call (.get exports tests) .for-files
        (list (path-expand "modules/example/tests/atomic-test.ss" root))))
      (check-equal? (.ref/cached tests 'build) #f)
      (def spec (.get tests std-make-spec))
      (check-equal? (map cadr spec) '("modules/example/tests/shared"))
      (check-equal? (file-exists? (path-expand "modules/example/tests/gerbil.pkg" root)) #f)
      (def windows 0)
      (parameterize ((current-module-source-observer
                      (lambda (kind amount)
                        (when (eq? kind 'read-windows) (set! windows (+ windows amount))))))
        ((.get tests admit-current)))
      (check-equal? windows 1)
      (def build (.get tests build))
      (check-equal? (eq? (.get build selected-graph) (.get tests selected-graph)) #t)
      ;; A source projection alone never grants product approval.
      (check-exception ((.get build admit-artifacts)) error?)
      (check-equal? (file-exists? (path-expand "harness-started" root)) #f)
      (check-equal? (file-exists? (path-expand "case-finished" root)) #f)
      (check-equal? (.ref/cached exports 'std-make-spec) #f)
      (forms root "modules/example/tests/shared.ss" '((export answer) (def answer 43)))
      (check-exception (.get tests std-make-spec) error?)
      (check-exception ((.get build admit-artifacts)) error?)
      (def changed (.call (.get exports tests) .for-files
        (list (path-expand "modules/example/tests/atomic-test.ss" root))))
      (check-equal? (equal? (.get (.get changed build) output-directory)
                           (.get build output-directory)) #f))
    (yuanxu-test-fixture "support projection failure never imports the Suite"
      (workspace TestPackage)
      (def root (.get workspace root))
      (write-source (path-expand "modules/example/tests/shared.ss" root) "(import")
      (def tests (.call (.get (exports-at root) tests) .for-files
        (list (path-expand "modules/example/tests/atomic-test.ss" root))))
      (check-exception (.get tests std-make-spec) syntax-error?)
      (check-equal? (file-exists? (path-expand "harness-started" root)) #f))))
