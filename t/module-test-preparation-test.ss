;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real init -> std/make -> issuance -> native Harness, with inert modules.
(import "./qualification/module-init/fixture.ss" :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/error Error? Error-message)
        (only-in :std/misc/ports read-all-as-u8vector read-all-as-string)
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
(def TestPackage
  ;; The canonical Just build stage prepared this Gerbil package. The Fixture
  ;; restores source bytes after fault injection, even when an assertion fails.
  (prepared-package-fixture
    (path-expand "qualification/native-preparation" (path-directory (this-source-file)))))
(def (exports-at root)
  (add-load-path! root)
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (import-fixture-init! (path-expand "init.ss" root) #t)))
;; Observe the Gerbil loader itself; do not substitute a hand-maintained module
;; table. The nonempty support Case below is the positive matcher control.
(def (artifact-runtime-loaded?)
  (ormap (lambda (entry)
           (string-prefix? "yuanxu/module-system/building/artifacts" (car entry)))
         (list-modules)))
(def module-test-preparation-test
  (test-suite "Automatic test preparation under native publication"
    (yuanxu-test-fixture "support-free files never demand selected declarations"
      (workspace TestPackage)
      (def root (.get workspace root))
      (forms root "modules/example/types.ss" '((error "business Types were demanded")))
      (forms root "modules/example/tests/plain-test.ss"
        '((import :std/test) (export plain-test)
          (def plain-test (test-suite "source-only native test"
            (test-case "real native Case" (check-equal? (+ 1 1) 2))))))
      (def exports (exports-at root))
      (def tests (.call (.get exports tests) .for-files
        (list (path-expand "modules/example/tests/plain-test.ss" root))))
      (check-equal? ((.get tests std-make-spec)) '())
      (check-equal? (artifact-runtime-loaded?) #f)
      (.call tests .compile)
      (check-equal? (artifact-runtime-loaded?) #f)
      (check-equal?
        (ormap (lambda (entry)
                 (string-prefix? "yuanxu/module-system/building/test-retention" (car entry)))
               (list-modules)) #f)
      (check-equal? (.ref/cached tests 'selected-graph) #f)
      (check-equal? (.ref/cached exports 'modules) #f)
      (check-equal? (.get (.call tests .run) status) 0)
      (check-equal? (artifact-runtime-loaded?) #f)
      (check-equal? (.ref/cached tests 'selected-graph) #f)
      (forms root "init.ss" '((error "changed init")))
      (check-exception (.call tests .run) error?))
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
      ;; Gerbil build issued the native support before either run. Both runs
      ;; execute their Cases; admission never substitutes a cached verdict.
      (check-exception (.call (.cc (.get tests execution) build: #f) .run) error?)
      (check-exception (.call (.cc (.get tests execution) build: #f) .compile) error?)
      (def prepared (.call tests .compile))
      (check-equal? (artifact-runtime-loaded?) #t)
      (check (eq? (.get prepared source) (.get tests source)) => #t)
      (check-equal? (file-exists? (path-expand "harness-started" root)) #f)
      (check-equal? (file-exists? (path-expand "case-finished" root)) #f)
      ((.get build admit-artifacts))
      (def cold (.call tests .run))
      (check-equal? (.get cold status) 0)
      (check-equal? (file-exists? (path-expand "harness-started" root)) #t)
      (check-equal? (file-exists? (path-expand "case-finished" root)) #t)
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
      ;; Even a semantically inert edit of an approved packet is a different
      ;; source. Digest-bound restoration must not accept a reparsed equivalent.
      (def approval (.get source reference))
      (def approval-text (call-with-input-file approval read-all-as-string))
      (dynamic-wind
        (lambda () (write-source approval (string-append approval-text "\n; replaced approval\n")))
        (lambda ()
          (def failure (with-catch values (lambda () ((.get fresh-build admit-artifacts)))))
          (check (Error? failure) => #t)
          (check-equal? (Error-message failure) "test approval source changed"))
        (lambda () (write-source approval approval-text)))
      ((.get fresh-build admit-artifacts))
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
        `((import :std/test "./shared.ss") (export atomic-test)
          (call-with-output-file ,marker (lambda (out) (display "started" out)))
          (def atomic-test (test-suite "never executed" (test-case "native" (void))))))
      (forms root "modules/example/tests/shared.ss"
        '((export answer) (def answer 42)
          (begin-foreign (c-declare "#error injected-test-support-compiler-failure"))))
      (def tests (.get (exports-at root) tests))
      ;; The test-only exception invokes the official compiler here so the
      ;; negative is a real C compiler failure, not just absent-file admission.
      (def failure
        (with-catch values
          (lambda ()
            (build-prepared-package! root (.get (.get tests execution) runtime-options)))))
      (check (Error? failure) => #t)
      (def diagnosis
        (call-with-output-string (lambda (out) (display-exception failure out))))
      (check (not (not (string-contains diagnosis "injected-test-support-compiler-failure"))) => #t)
      (check-exception (.call tests .run) error?)
      (check-equal? (file-exists? marker) #f))))
