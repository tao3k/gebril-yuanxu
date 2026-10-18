;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Testing policy over Ops and the original std/test harness, not a runner.
(import :clan/poo/object
        (only-in :std/misc/ports read-all-as-string)
        (only-in :core/ops/objects ProcessScript.)
        (only-in :core/ops/func run-script)
        (only-in "./testing-case.ss" poo-flow-current-testing-case-profile
                 poo-flow-testing-case-profile?)
        (only-in "./testing-fixture.ss" call-with-poo-flow-fixture))
(export TestingScript. admit-testing-result testing-script-for-source)

;; Called only at the explicit execution boundary, never while selecting init.
(def (testing-script-for-source source)
  (.cc TestingScript. 'source source))

(def (check-testing-spec files)
  ;; Empty gxtest argv means "discover this directory", not "run no tests".
  (unless (and (list? files) (pair? files)
               (andmap (lambda (file) (and (string? file) (not (string-empty? file)))) files))
    (error "testing spec requires explicit nonempty native harness inputs" files)))

(def (admit-testing-result result files)
  (check-testing-spec files)
  (def output (.get result output))
  (unless (and (eqv? (.get result status) 0) (string? output))
    (error "native test process did not succeed" files (.get result status) output))
  (when (ormap (cut string-contains output <>)
               '("ERROR MODULE" "ERROR CASE" "ERROR CHECK" "ERROR HARNESS"
                 "Heap overflow" "Stack overflow" "*** ERROR"))
    (error "native test harness reported failure" files (.get result status) output))
  (let (lines (string-split output #\newline))
    (unless (and (andmap (lambda (file) (member (string-append "MODULE-OK " file) lines)) files)
                 (member (string-append "HARNESS-OK " (object->string files)) lines)
                 (member "OK" lines))
      (error "native test harness completion is missing" files (.get result status) output)))
  result)

;; gxtest already performs native package-environment setup. The extra gxpkg
;; process is unnecessary when the caller has ALSO installed its bin priority.
;; Recheck effective overrides at each .run, never cache this environment fact.
(def (testing-execution-script script files)
  (def native-command (append '("gerbil") (.get script runtime-options) '("test") files))
  (def declared-command (.get script command))
  (def overrides (.get script environment))
  (def (setting name)
    (if (.slot? overrides name) (.ref overrides name) (getenv (symbol->string name) #f)))
  (def root (setting 'GERBIL_PATH))
  (def path (setting 'PATH))
  (def prepared?
    (and (string? root) (not (string-empty? root)) (string? path) (not (string-empty? path))
         (equal? (car (string-split path #\:)) (string-append root "/bin"))))
  (cond
   ((not (equal? declared-command native-command)) script)
   (prepared?
    ;; Freeze the pair whose priority was checked into the actual Ops request;
    ;; later ambient changes cannot invalidate the launch decision.
    (.cc script 'environment (.+ overrides (.o GERBIL_PATH: root PATH: path))))
   (else
    ;; Delegate missing initialization to the original tool; do not copy its
    ;; directory/package lookup or silently change explicitly different commands.
    (.cc script 'command
      ;; gxpkg env spawns a child; VM flags on its dispatcher are not inherited.
      (append '("gerbil") (.get script runtime-options) '("env" "gerbil")
              (.get script runtime-options) '("test") files)))))

(def (run-testing-script script)
  (def source (.get script source))
  (unless (and (object? source) (.slot? source 'spec) (.slot? source 'admit-current))
    (error "testing requires a source object binding spec and currentness"))
  (def files (.get source spec))
  (def current! (.get source admit-current))
  (check-testing-spec files)
  (unless (and (procedure? current!)
               (poo-flow-testing-case-profile? (.get script profile))
               (> (.get script profile heap-limit-bytes) 0))
    (error "invalid testing script guard or resource profile"))
  ;; The existing fixture boundary retains both process and post-check errors.
  (call-with-poo-flow-fixture
    (.o .acquire: (lambda () (current!) files)
        .release: (lambda (_files) (current!)))
    (lambda (_files)
      (let* ((receipt (run-script (testing-execution-script script files)))
             (result (if (.get receipt log)
                       (.cc receipt 'output
                         (call-with-input-file (.get receipt log) read-all-as-string))
                       receipt)))
        (admit-testing-result result files)))))

(.def (TestingScript. script [ProcessScript.])
  source: #f
  directory: (if (.slot? (.get script source) 'source-root)
               (.get script source source-root)
               (.get script config directory))
  profile: (poo-flow-current-testing-case-profile)
  runtime-options:
  (let (bytes (.get script profile heap-limit-bytes))
    ;; Gambit defaults unsuffixed sizes to KiB. Do not turn a byte budget into
    ;; a cap 1024 times larger; round down rather than exceed the policy.
    (when (< bytes 1024) (error "native test heap budget must be at least one KiB" bytes))
    (list (string-append "-:max-heap="
            (number->string (quotient bytes 1024)) "K,debug=q")))
  command: (append '("gerbil") (.get script runtime-options) '("test") (.get script source spec))
  timeout: (/ (.get script profile max-duration-milliseconds) 1000)
  .run: (lambda () (run-testing-script script)))
