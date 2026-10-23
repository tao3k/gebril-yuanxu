;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real init -> std/make -> issuance -> native Harness, with inert modules.
(import "./qualification/module-init/fixture.ss" :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :std/misc/ports read-all-as-u8vector)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture write-source))
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
    ;; The requested test lives in an aligned nested package. Native Make must
    ;; still receive a root-relative target, never the absolute source path.
    (forms root "modules/example/tests/gerbil.pkg"
      `((package: ,(string->symbol
                    (string-append (symbol->string package-name) "/modules/example/tests")))))
    (forms root "init.ss"
      '((import :yuanxu/module-system/selection/init-syntax)
        (yuanxu! mode: explicit source: "./modules" (example))))
    (forms root "modules/example/types.ss"
      '((import :clan/poo/object (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract))
        (def Scope (yuanxu-predicate-contract 'test/scope object? (lambda (_v _c) '())))
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
      '((import :std/test "./shared.ss") (export atomic)
        (def atomic (test-suite "prepared native support"
          (test-case "compiled helper" (check-equal? answer 42))))))
    workspace))
(def (exports-at root)
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (import-fixture-init! (path-expand "init.ss" root))))
(def module-test-preparation-test
  (test-suite "Automatic test preparation under native publication"
    (yuanxu-test-fixture "narrow cold/hot compilation, isolated issuance and source refusal"
      (workspace TestPackage)
      (def root (.get workspace root))
      (def exports (exports-at root))
      (check-equal? (.ref/cached exports 'tests) #f)
      (def tests
        (.call (.get exports tests) .for-files
          (list (path-expand "modules/example/tests/atomic-test.ss" root))))
      (check-equal? (.ref/cached tests 'build) #f)
      (check-equal? (.ref/cached tests 'execution) #f)
      (def spec ((.get tests std-make-spec)))
      (check-equal? (map cadr spec) '("modules/example/tests/shared"))
      ;; One explicit file-source guard checks selection once. Observation is
      ;; local to this call; no check result survives Make or Harness effects.
      (def windows 0)
      (parameterize ((current-module-source-observer
                      (lambda (kind amount)
                        (when (eq? kind 'read-windows) (set! windows (+ windows amount))))))
        ((.get tests admit-current)))
      (check-equal? windows 1)
      (def build (.get tests build))
      (check (eq? (.get build selected-graph) (.get tests selected-graph)) => #t)
      (check-exception ((.get build admit-artifacts)) error?)
      ;; The first run compiles the shared unit; the second lets std/make reuse
      ;; the same issued native outputs. Neither run caches a passing verdict.
      (check-exception (.call (.cc (.get tests execution) build: #f) .run) error?)
      (def cold (.call tests .run))
      (check-equal? (.get cold status) 0)
      (def lib (.get build output-directory))
      (def identity (symbol->string (car (.get build compiler-identities))))
      (def output (path-expand (string-append identity ".o1") lib))
      (def before (time->seconds (file-info-last-modification-time (file-info output))))
      (def hot (.call tests .run))
      (check-equal? (.get hot status) 0)
      (check-equal? (time->seconds (file-info-last-modification-time (file-info output))) before)
      (check-equal? (file-exists? (path-expand (string-append identity ".o2") lib)) #f)
      ;; Another receiver restores the same approved native handoff rather than
      ;; inheriting this receiver's in-memory publication or adopting its files.
      (def fresh (.call (.get exports tests) .for-files
        (list (path-expand "modules/example/tests/atomic-test.ss" root))))
      (def fresh-build (.get fresh build))
      (check (eq? (.get build build-graph) (.get fresh-build build-graph)) => #f)
      (check-equal? (.get fresh-build output-directory) lib)
      (check-equal? (.get (.call fresh .run) status) 0)
      (check-equal? (time->seconds (file-info-last-modification-time (file-info output))) before)
      ;; A joint product/sidecar replacement cannot rewrite the package-owned
      ;; approval. Restore bytes in cleanup even if the refusal assertion fails.
      (def source (.get fresh-build build-graph build-publication))
      (def packet (call-with-input-file (.get source reference) read))
      (def record (list-ref packet 5))
      (def originals (map (lambda (path) (cons path (call-with-input-file path read-all-as-u8vector)))
                         (list output record)))
      (dynamic-wind
        (lambda ()
          (write-source output "replaced native product")
          (write-source record "(replaced native record)"))
        (lambda ()
          (def failure (with-catch values (lambda () ((.get fresh-build admit-artifacts)))))
          (check (Error? failure) => #t)
          (check-equal? (Error-message failure) "test approved issuance record changed"))
        (lambda ()
          (for-each
            (lambda (row)
              (call-with-output-file (list path: (car row) truncate: #t)
                (lambda (port) (write-subu8vector (cdr row) 0 (u8vector-length (cdr row)) port))))
            originals)))
      ((.get build admit-artifacts))
      (check-equal? (.ref/cached exports 'std-make-spec) #f)
      (forms root "modules/example/tests/shared.ss" '((export answer) (def answer 43)))
      (check-exception (.call tests .run) error?)
      (check-exception ((.get build admit-artifacts)) error?)
      (def changed (.call (.get exports tests) .for-files
        (list (path-expand "modules/example/tests/atomic-test.ss" root))))
      (check (equal? (.get (.get changed build) output-directory) lib) => #f))
    (yuanxu-test-fixture "preparation failure never starts Harness"
      (workspace TestPackage)
      (def root (.get workspace root))
      (def marker (path-expand "harness-started" root))
      (forms root "modules/example/tests/atomic-test.ss"
        `((import :std/test "./shared.ss") (export atomic)
          (call-with-output-file ,marker (lambda (out) (display "started" out)))
          (def atomic (test-suite "never executed" (test-case "native" (void))))))
      (forms root "modules/example/tests/shared.ss"
        '((export answer) (def answer 42)
          (begin-foreign (c-declare "#error injected-test-support-compiler-failure"))))
      (def tests (.get (exports-at root) tests))
      (def failure (with-catch values (cut .call tests .run)))
      (check (Error? failure) => #t)
      (def diagnosis
        (call-with-output-string (lambda (out) (display-exception failure out))))
      (check (not (not (string-contains diagnosis "injected-test-support-compiler-failure"))) => #t)
      (check-equal? (file-exists? marker) #f))))
