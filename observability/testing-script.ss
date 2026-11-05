;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Testing policy over Ops and the original std/test harness, not a runner.
(import :clan/poo/object
        (only-in :yuanxu/ops/progress make-test-progress-reader call-with-execution-watchdog execution-progress!)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/ops/func run-script)
        (only-in "./testing-case.ss" yuanxu-selected-testing-case-profile
                 yuanxu-testing-case-profile? yuanxu-test-checkpoint)
        (only-in "./testing-fixture.ss" call-with-yuanxu-fixture))
(export TestingScript. admit-testing-result admit-testing-process-result make-compiler-progress-reader)

;; One explicit .run owns one deadline, including source and final admission. This
;; dynamic extent is not a cached result and is restored on failure/nesting.
(def current-testing-deadline (make-parameter #f))
(def (limit-testing-script script)
  (let (deadline (current-testing-deadline))
    (if (not deadline) script
      (let (remaining (exact->inexact (/ (- deadline (current-jiffy)) (jiffies-per-second))))
        (unless (> remaining 0) (error "test file budget exhausted before process launch"))
        ;; GNU timeout accepts fractional seconds. Keep its hard process-group
        ;; boundary; preparation must not reset the Harness's remaining budget.
        (.cc script 'timeout
          (if (.get script timeout) (min remaining (.get script timeout)) remaining))))))

;; Relay completed native build and source-index work through the existing Ops
;; frame. An index result is still admitted separately from liveness.
(def (make-compiler-progress-reader)
  (def completed 0)
  ;; Counts restart for each actual compiler process. Its identity must restart
  ;; too, or an enclosing build/clean/rebuild frame ignores all later work
  ;; until the new child happens to exceed the previous child's count.
  (def compiler (gensym 'compiler))
  (make-test-progress-reader
    (lambda (line)
      (when (or (string-prefix? "... compile " line)
                (string-prefix? "... invoke " line)
                (string-prefix? "... remove " line)
                (string-prefix? "... execute compile job " line)
                (and (string-prefix? "TAG " line) (> (string-length line) 4)))
        (set! completed (+ completed 1))
        (execution-progress! compiler completed)))))

;; Use the original harness's feature channel, not an environment probe or a
;; second launcher. Only observation booleans cross this process boundary;
;; arbitrary procedures and prototype identities are never serialized.
(def (testing-harness-options script)
  (if (.get script profile emit?)
    ;; gxtest accepts one comma-separated -D, not repeated options.
    (list "-D"
      (if (and (.slot? (.get script profile) 'trace-enabled?)
               (.get script profile trace-enabled?))
        "yuanxu-module-test-observation,yuanxu-module-test-trace"
        "yuanxu-module-test-observation"))
    '()))

(def (check-testing-spec files)
  ;; Empty gxtest argv means "discover this directory", not "run no tests".
  (unless (and (list? files) (pair? files)
               (andmap (lambda (file) (and (string? file) (not (string-empty? file)))) files))
    (error "testing spec requires explicit nonempty runtime harness inputs" files)))

(def (admit-testing-process-result result files)
  (check-testing-spec files)
  (def output (.get result output))
  (unless (and (eqv? (.get result status) 0) (string? output))
    (error "runtime test process did not succeed" files (.get result status) output))
  (when (ormap (cut string-contains output <>)
               '("ERROR MODULE" "ERROR CASE" "ERROR CHECK" "ERROR HARNESS"
                 "Heap overflow" "Stack overflow" "*** ERROR"))
    (error "runtime test harness reported failure" files (.get result status) output))
  (unless (member "OK" (string-split output #\newline))
    (error "runtime test harness completion is missing" files (.get result status) output))
  result)

(def (admit-testing-result result files)
  (admit-testing-process-result result files)
  (let (lines (string-split (.get result output) #\newline))
    (unless (and (andmap (lambda (file) (member (string-append "MODULE-OK " file) lines)) files)
                 (member (string-append "HARNESS-OK " (object->string files)) lines)
                 (member "OK" lines))
      (error "runtime test harness completion is missing" files (.get result status) (.get result output))))
  result)

(def (admit-testing-script-result script result)
  (def files (.get script source spec))
  (def harness (.get script harness))
  (if harness
    (admit-testing-process-result result files)
    (admit-testing-result result files))
  (def lines (string-split (.get result output) #\newline))
  (def required
    (append (.get script required-lines)
      (if harness
        (cons harness (map (cut string-append "MODULE-OK " <>) files)) '())))
  (for-each
    (lambda (line)
      (unless (member line lines)
        (error "qualification receipt is missing" line files (.get result output))))
    required)
  (let (expected (.get script case-count))
    (when expected
      (let (actual (length (filter (cut string-prefix? "CASE-OK " <>) lines)))
        (unless (= expected actual)
          (error "qualification case count mismatch" files expected actual (.get result output))))))
  (when (string-contains (.get result output) "WARNING -- Variable")
    (error "qualification contains an undefined binding warning" files (.get result output)))
  result)


;; Explicit external-process qualifications retain their source guard. Ordinary
;; module tests are std/test inputs; this boundary never prepares or compiles.
(def (call-with-testing-source script action)
  (def source (.get script source))
  (unless (and (object? source) (.slot? source 'spec) (.slot? source 'admit-current))
    (error "testing requires a source object binding spec and currentness"))
  (def files (.get source spec))
  (def current! (.get source admit-current))
  (check-testing-spec files)
  (unless (and (procedure? current!)
               (yuanxu-testing-case-profile? (.get script profile))
               (> (.get script profile heap-limit-bytes) 0))
    (error "invalid testing script guard or resource profile"))
  ;; The existing Fixture retains both the process failure and post-check error.
  (call-with-yuanxu-fixture
    (.o .acquire: (lambda () (current!) files)
        .release: (lambda (_files) (current!)))
    (lambda (_files) (action script files))))

(def (run-testing-script script)
  (def milliseconds (.get script profile max-duration-milliseconds))
  (parameterize ((current-testing-deadline
                   (+ (current-jiffy) (* (/ milliseconds 1000) (jiffies-per-second)))))
    (call-with-execution-watchdog #f milliseconds
      (lambda ()
        (call-with-testing-source script
          (lambda (script files)
            (yuanxu-test-checkpoint 'test-worker-launch)
            (let* ((receipt (run-script
                             (limit-testing-script script)))
                   (result (if (.get receipt log)
                             (.cc receipt 'output
                               (call-with-input-file (.get receipt log) read-all-as-string))
                             receipt)))
              (yuanxu-test-checkpoint 'test-worker-returned)
              ;; Specialized receipt policy cannot bypass the common gate.
              (admit-testing-process-result result files)
              (.call script .admit-result result))))))))

(.def (TestingScript. script [ProcessScript.])
  source: #f
  directory: (if (.slot? (.get script source) 'source-root)
               (.get script source source-root)
               (.get script config directory))
  profile: (yuanxu-selected-testing-case-profile)
  runtime-options:
  (let (bytes (.get script profile heap-limit-bytes))
    ;; Gambit defaults unsuffixed sizes to KiB. Do not turn a byte budget into
    ;; a cap 1024 times larger; round down rather than exceed the policy.
    (when (< bytes 1024) (error "runtime test heap budget must be at least one KiB" bytes))
    (list (string-append "-:max-heap="
            (number->string (quotient bytes 1024)) "K,debug=q")))
  command: (append '("gerbil") (.get script runtime-options) '("test")
                   (testing-harness-options script) (.get script source spec))
  timeout: (/ (.get script profile max-duration-milliseconds) 1000)
  idle-timeout: (/ (.get script profile max-idle-milliseconds) 1000)
  progress: make-test-progress-reader
  ;; Specialized runtime harnesses refine receipt admission, never process or
  ;; Fixture execution. The default keeps the original exact harness protocol.
  case-count: #f
  harness: #f
  required-lines: '()
  .admit-result: (lambda (result) (admit-testing-script-result script result))
  .run: (lambda () (run-testing-script script)))
