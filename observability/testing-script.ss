;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Testing policy over Ops and the original std/test harness, not a runner.
(import :clan/poo/object
        (only-in :yuanxu/ops/progress make-test-progress-reader call-with-execution-watchdog execution-progress!)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/ops/func run-script)
        (only-in :yuanxu/module-system/building/artifacts current-build-phase-times)
        (only-in "./testing-case.ss" yuanxu-selected-testing-case-profile
                 yuanxu-testing-case-profile? yuanxu-test-checkpoint)
        (only-in "./testing-fixture.ss" call-with-yuanxu-fixture))
(export TestingScript. admit-testing-result admit-testing-process-result testing-script-for-source make-compiler-progress-reader)

;; Relay only real std/make work through the existing Ops progress frame.
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
                (string-prefix? "... execute compile job " line))
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

;; Called only at the explicit execution boundary, never while selecting init.
(def (testing-script-for-source source-value (build-accessor #f))
  (.o (:: script [TestingScript.])
      source: source-value build: build-accessor
      ;; Bind the required compiler association at publication. A child Script
      ;; can refine its execution policy, but cannot silently erase preparation.
      .run: (lambda () (run-testing-script script build-accessor))))

(def (check-testing-spec files)
  ;; Empty gxtest argv means "discover this directory", not "run no tests".
  (unless (and (list? files) (pair? files)
               (andmap (lambda (file) (and (string? file) (not (string-empty? file)))) files))
    (error "testing spec requires explicit nonempty native harness inputs" files)))

(def (admit-testing-process-result result files)
  (check-testing-spec files)
  (def output (.get result output))
  (unless (and (eqv? (.get result status) 0) (string? output))
    (error "native test process did not succeed" files (.get result status) output))
  (when (ormap (cut string-contains output <>)
               '("ERROR MODULE" "ERROR CASE" "ERROR CHECK" "ERROR HARNESS"
                 "Heap overflow" "Stack overflow" "*** ERROR"))
    (error "native test harness reported failure" files (.get result status) output))
  (unless (member "OK" (string-split output #\newline))
    (error "native test harness completion is missing" files (.get result status) output))
  result)

(def (admit-testing-result result files)
  (admit-testing-process-result result files)
  (let (lines (string-split (.get result output) #\newline))
    (unless (and (andmap (lambda (file) (member (string-append "MODULE-OK " file) lines)) files)
                 (member (string-append "HARNESS-OK " (object->string files)) lines)
                 (member "OK" lines))
      (error "native test harness completion is missing" files (.get result status) (.get result output))))
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


;; gxtest owns package-environment setup. Freeze an existing package root and
;; its bin priority into the Ops request instead of spawning gxpkg just for PATH.
;; Missing package context still delegates discovery to the original SDK.
(def (testing-execution-script script files)
  (def native-command
    (append '("gerbil") (.get script runtime-options) '("test")
            (testing-harness-options script) files))
  (def declared-command (.get script command))
  (def overrides (.get script environment))
  (def (setting name)
    (if (.slot? overrides name) (.ref overrides name) (getenv (symbol->string name) #f)))
  (def root (setting 'GERBIL_PATH))
  (def path (setting 'PATH))
  (def prepared?
    (and (string? root) (not (string-empty? root)) (string? path) (not (string-empty? path))))
  (cond
   ((not (equal? declared-command native-command)) script)
   (prepared?
    ;; Freeze the pair whose priority was checked into the actual Ops request;
    ;; later ambient changes cannot invalidate the launch decision.
    (.cc script 'environment
      (.+ overrides
        (.o GERBIL_PATH: root
            PATH: (if (equal? (car (string-split path #\:)) (string-append root "/bin"))
                    path (string-append root "/bin:" path))))))
   (else
    ;; Delegate missing initialization to the original tool; do not copy its
    ;; directory/package lookup or silently change explicitly different commands.
    (.cc script 'command
      ;; gxpkg env spawns a child; VM flags on its dispatcher are not inherited.
      (append '("gerbil") (.get script runtime-options) '("env" "gerbil")
              (.get script runtime-options) '("test")
              (testing-harness-options script) files)))))

;; Native std/make is the sole compiler/dependency scheduler. The Script only
;; brackets that existing compiler with the same issuance and Fixture boundary.
(def (prepare-testing-script script files build)
  (when build
    (unless (and (eq? (.get build demand-source) (.get script source))
                 ;; An empty support spec grants no compilation authority.
                 ;; Keep Graph demand lazy until there are products to issue.
                 (or (null? (.get build spec))
                     (eq? (.get build selected-graph) (.get script source selected-graph))))
      (error "test compiler projection belongs to another demand")))
  (if (or (not build) (null? (.get build spec))) script
    (let ((started (real-time))
          (times (and (.get script profile emit?) (make-hash-table-eq))))
      (def compilation
       (parameterize ((current-build-phase-times times))
       (.call build .compile (.get build output-directory)
        (lambda ()
          (def expression
            `(let (started (real-time))
               (make ',(.get build spec) srcdir: ,(.get build source-root)
                 libdir: ,((.get build compile-output)))
               ,@(if times
                   '((displayln "test-prepare phase=std-make seconds=" (- (real-time) started)))
                   '())))
          (when (and times (.slot? (.get script profile) 'trace-enabled?)
                     (.get script profile trace-enabled?))
            (displayln "test-prepare phase=make-request expression=" (object->string expression)))
          (def environment (.get (testing-execution-script script files) environment))
          (def prepared?
            (and (.slot? environment 'GERBIL_PATH) (.slot? environment 'PATH)
                 (string? (.get environment GERBIL_PATH)) (string? (.get environment PATH))
                 (not (string-empty? (.get environment GERBIL_PATH)))
                 (not (string-empty? (.get environment PATH)))))
          (def receipt (run-script
            (.cc ProcessScript.
              'directory (.get script directory)
              'environment (.+ environment (.o GERBIL_BUILD_CORES: "1" GERBIL_BUILD_VERBOSE: "1"))
              'progress make-compiler-progress-reader
              'timeout 120 'idle-timeout 60
              'command
              (append
                (if prepared? '("gxi")
                  (append '("gerbil") (.get script runtime-options) '("env" "gxi")))
                (.get script runtime-options)
                (append
                  (if times '("-e" "(define test-make-started (real-time))") '())
                  (list "-e" "(import :std/make)")
                  (if times
                    '("-e" "(displayln \"test-prepare phase=make-import seconds=\" (- (real-time) test-make-started))")
                    '())
                  (list "-e" (object->string expression)))))))
          ;; Report the actual compiler before completion admission: a refused
          ;; new generation must not erase the producer's diagnostic counts.
          (when times
            (displayln "test-prepare phase=make-process seconds=" (.get receipt seconds)
              " compile-count="
              (length (filter (cut string-prefix? "... compile " <>)
                        (string-split (.get receipt output) #\newline))))
            (for-each displayln
              (filter (cut string-prefix? "test-prepare phase=" <>)
                (string-split (.get receipt output) #\newline))))
          receipt))))
      (when (.get script profile emit?)
        (displayln "test-prepare phase=compile seconds=" (- (real-time) started)
          " make-seconds=" (.get compilation seconds)
          " compile-count="
          (length (filter (cut string-prefix? "... compile " <>)
                    (string-split (.get compilation output) #\newline)))))
      (parameterize ((current-build-phase-times times)) ((.get build admit-artifacts)))
      (when times
        (displayln "test-prepare phase=recovery seconds=" (or (hash-get times 'recovery) 0)
          " currentness-seconds=" (or (hash-get times 'currentness) 0)
          " publication-lookup-seconds=" (or (hash-get times 'publication-lookup) 0)
          " publication-lookups=" (or (hash-get times 'publication-lookups) 0)))
      (let* ((environment (.get script environment))
             (prior (if (.slot? environment 'GERBIL_LOADPATH)
                      (.get environment GERBIL_LOADPATH) (getenv "GERBIL_LOADPATH" ""))))
        (.cc script 'environment
          (.+ environment
            (.o GERBIL_LOADPATH:
              (string-append (.get build output-directory)
                (if (string-empty? prior) "" (string-append ":" prior))))))))))

(def (run-testing-script script (required-build #f))
  (when (and required-build (not (eq? required-build (.get script build))))
    (error "declared test compiler association cannot be replaced or removed"))
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
  (def compiled #f)
  ;; The existing fixture boundary retains both process and post-check errors.
  (call-with-yuanxu-fixture
    (.o .acquire: (lambda () (current!) files)
        .release: (lambda (_files)
                    (when compiled ((.get compiled admit-artifacts)))
                    (current!)))
    (lambda (_files)
      (def preparation-started (real-time))
      (def build
        (call-with-execution-watchdog #f 120000
          (lambda ()
            (let (value (and (.get script build) ((.get script build))))
              (when (.get script profile emit?)
                (displayln "test-prepare phase=projection seconds="
                  (- (real-time) preparation-started)
                  " support-count=" (if value (length (.get value spec)) 0)))
              (when (and required-build (not (object? value)))
                (error "declared test support requires a compiler projection"))
              (set! script (prepare-testing-script script files value))
              value))))
      (when (and build (pair? (.get build spec))) (set! compiled build))
      (yuanxu-test-checkpoint 'test-worker-launch)
      (let* ((receipt (run-script (testing-execution-script script files)))
             (result (if (.get receipt log)
                       (.cc receipt 'output
                         (call-with-input-file (.get receipt log) read-all-as-string))
                       receipt)))
        (yuanxu-test-checkpoint 'test-worker-returned)
        ;; Refining a specialized receipt cannot bypass the common process gate.
        (admit-testing-process-result result files)
        (.call script .admit-result result)))))

(.def (TestingScript. script [ProcessScript.])
  source: #f
  build: #f
  directory: (if (.slot? (.get script source) 'source-root)
               (.get script source source-root)
               (.get script config directory))
  profile: (yuanxu-selected-testing-case-profile)
  runtime-options:
  (let (bytes (.get script profile heap-limit-bytes))
    ;; Gambit defaults unsuffixed sizes to KiB. Do not turn a byte budget into
    ;; a cap 1024 times larger; round down rather than exceed the policy.
    (when (< bytes 1024) (error "native test heap budget must be at least one KiB" bytes))
    (list (string-append "-:max-heap="
            (number->string (quotient bytes 1024)) "K,debug=q")))
  command: (append '("gerbil") (.get script runtime-options) '("test")
                   (testing-harness-options script) (.get script source spec))
  timeout: (/ (.get script profile max-duration-milliseconds) 1000)
  idle-timeout: (/ (.get script profile max-idle-milliseconds) 1000)
  progress: make-test-progress-reader
  ;; Specialized native harnesses refine receipt admission, never process or
  ;; Fixture execution. The default keeps the original exact harness protocol.
  case-count: #f
  harness: #f
  required-lines: '()
  .admit-result: (lambda (result) (admit-testing-script-result script result))
  .run: (lambda () (run-testing-script script)))
