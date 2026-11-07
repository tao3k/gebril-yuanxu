;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Scheme owns serial dispatch and receipts; Gerbil owns the Harness and verdict.
(import (only-in :clan/poo/object .o .cc .get)
        (only-in :gerbil/expander core-import-module module-context-path)
        (only-in :gerbil/runtime/loader load-path)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/encoding/json json->string)
        (only-in :std/io/tempfile make-temporary-file-name current-temporary-directory)
        (only-in :std/list/list delete-duplicates/hash take)
        (only-in :std/misc/ports read-all-as-string read-all-as-u8vector)
        (only-in :yuanxu/ops/func run-script)
        (only-in :yuanxu/ops/progress execution-idle-seconds)
        (only-in :yuanxu/ops/process-script ProcessScript.))
(export main)

(def (elapsed-milliseconds started)
  (quotient (* (- (current-jiffy) started) 1000) (jiffies-per-second)))

(def (main action . arguments)
  (cond ((equal? action "--audit") (apply audit-report arguments))
        ((equal? action "--compare") (apply compare-reports arguments))
        ((equal? action "--list") (for-each displayln (apply discovered-files arguments)))
        ((equal? action "--check-partition") (check-partition))
        ((equal? action "--qualification")
         (match arguments
           ([runtime-options] (write (qualification-cohort runtime-options #t)) (newline))
           (else (error "qualification requires the test runtime options" arguments))))
        ((equal? action "--platform") (apply report-platform arguments))
        ((equal? action "--mutate-build-input") (apply verify-build-input-mutations arguments))
        (else (unless (apply report-group action arguments) (exit 1)))))

(def test-groups
  '("dense-declarations" "dense-selection" "dense-values" "modules" "runtime" "contracts" "bootstrap"))
(def (group-owner file)
  (case (string->symbol file)
    ((module-declaration-10000-test.ss) "dense-declarations")
    ((module-runtime-selection-10000-test.ss) "dense-selection")
    ((module-runtime-values-10000-test.ss) "dense-values")
    ((module-runtime-values-1000-test.ss module-runtime-attribution-1000-test.ss) "bootstrap")
    ((module-runtime-selection-1000-test.ss) "runtime")
    ((thousand-package-downstream-test.ss module-declaration-1000-test.ss
      module-business-sparse-10000-test.ss module-declaration-retention-test.ss
      module-loading-scale-test.ss) "contracts")
    (else
     (cond ((ormap (cut string-prefix? <> file)
                   '("package-" "prelude-" "core-build-" "module-build-" "module-bootstrap-"
                     "runtime-publication-identity-")) "bootstrap")
           ((ormap (cut string-prefix? <> file) '("module-" "feature-system-")) "modules")
           ((ormap (cut string-prefix? <> file)
                   '("json-schema-" "source-" "contract-" "admission-" "contribution-"
                     "configuration-" "poo-" "object-" "issued-" "path-" "evidence-"
                     "issuer-" "aws-" "gitea-" "nix-" "ops-")) "contracts")
           (else "runtime")))))

(def (discovered-files group)
  (unless (or (equal? group "all") (member group test-groups))
    (error "unknown test group" group))
  (filter-map (lambda (file)
                (and (string-suffix? "-test.ss" file)
                     (or (equal? group "all") (equal? group (group-owner file)))
                     (string-append "t/" file)))
              (list-sort string<? (directory-files "t"))))

(def (check-partition)
  (def groups (map discovered-files test-groups))
  (unless (and (andmap pair? groups)
               (equal? (discovered-files "all")
                       (list-sort string<? (apply append groups))))
    (error "missing or duplicated test group coverage"))
  (for-each (lambda (group files) (displayln "TEST-GROUP " group " files=" (length files)))
            test-groups groups)
  (displayln "TEST-GROUPS-OK"))

(def (report-root)
  (let (report (getenv "YUANXU_TEST_REPORT_DIR" ""))
    (if (string-empty? report) (make-temporary-file-name "yuanxu-test-report-") report)))

(def (qualification-field cohort key)
  (cond ((assq key (cdr cohort)) => cdr)
        (else #f)))

(def (qualification-build-matches? cohort)
  (def source (qualification-field cohort 'source))
  (and source
       (qualification-field cohort 'clean?)
       (equal? source (qualification-field cohort 'build-source))
       (qualification-field cohort 'package-declaration)
       (qualification-field cohort 'just)
       (qualification-field cohort 'poo)
       (qualification-field cohort 'release-manifest)))

(def (qualification-cohort runtime-options (required? #f))
  (def (command-output command)
    (def result
      (run-script (.cc ProcessScript. command: command check-status: #f)))
    (and (zero? (.get result status)) (.get result output)))
  (def (digest-file path)
    (and (file-exists? path)
         (hex-encode (sha256 (call-with-input-file path read-all-as-u8vector)))))
  (def source (command-output '("git" "rev-parse" "HEAD")))
  (def changes (command-output '("git" "status" "--porcelain" "--untracked-files=normal")))
  (def source-id (and source (car (string-split source #\newline))))
  (def clean? (and changes (string-empty? changes)))
  (def prefix (getenv "GERBIL_PATH"))
  (def build-record (path-expand "test-build-source" prefix))
  (def build-source (and (file-exists? build-record) (call-with-input-file build-record read-line)))
  (def checkout (path-expand "pkg/github.com/tao3k/gerbil-poo" prefix))
  (def poo (and (file-exists? checkout) (command-output ["git" "-C" checkout "rev-parse" "HEAD"])))
  (def just-version (command-output '("just" "--version")))
  (def core-origin (module-context-path (core-import-module ':yuanxu/ops/func)))
  (def poo-origin (module-context-path (core-import-module ':clan/poo/object)))
  (def release
    (digest-file (path-expand "../gerbil-toolchain-release.json" (gerbil-home))))
  (def cohort
    (list 'test-qualification
          (cons 'source source-id) (cons 'build-source build-source) (cons 'clean? clean?)
          (cons 'package-declaration (digest-file "gerbil.pkg"))
          (cons 'gerbil (gerbil-version-string))
          (cons 'gambit (system-version-string))
          (cons 'just (and just-version (car (string-split just-version #\newline))))
          (cons 'release-manifest release)
          (cons 'poo (and poo (car (string-split poo #\newline))))
          (cons 'core-origin core-origin)
          (cons 'poo-origin poo-origin)
          (cons 'load-path (load-path))
          (cons 'runtime-options runtime-options)
          (cons 'build-cores (getenv "GERBIL_BUILD_CORES" #f))
          (cons 'idle-seconds execution-idle-seconds)
          (cons 'worker-seconds test-worker-seconds)))
  (def ci? (equal? (getenv "GITHUB_ACTIONS" "") "true"))
  (def lib-root
    (string-append (path-strip-trailing-directory-separator
                     (path-normalize (path-expand "lib" prefix))) "/"))
  (def (installed-origin? origin)
    (and (string? origin) (string-prefix? lib-root (path-normalize origin))))
  (when (or required? ci?)
    (unless (and (qualification-build-matches? cohort)
                 (or (not ci?) (equal? source-id (getenv "GITHUB_SHA" #f)))
                 (installed-origin? core-origin)
                 (installed-origin? poo-origin))
      (error "qualification requires a clean checkout and its matching installed build"
             cohort)))
  cohort)

(def test-worker-seconds 600)

(def (report-platform runtime-options)
  (check-partition)
  (def root (report-root))
  (def cohort (qualification-cohort runtime-options))
  (def passed? #t)
  (for-each (lambda (group)
              (unless (report-group group runtime-options (path-expand group root) cohort)
                (set! passed? #f)))
            test-groups)
  (audit-report root)
  (unless passed? (exit 1)))

(def (report-group group runtime-options (report (report-root))
                   (qualification (qualification-cohort runtime-options)))
  ;; One worker at a time with the original per-file budgets and receipt.
  (def started (current-jiffy))
  (def files (discovered-files group))
  (unless (and (pair? files) (= (length files) (length (delete-duplicates/hash files))))
    (error "missing or duplicated files in the discovered test group" group))
  (create-directory* report)
  (call-with-output-file (path-expand "qualification.ss" report)
    (lambda (port) (write qualification port) (newline port)))
  (display "TEST-QUALIFICATION ") (write qualification) (newline)
  (call-with-output-file (path-expand "expected-files.ss" report)
    (lambda (port) (write files port) (newline port)))
  (displayln "TEST-REPORT " report)
  (def outcomes '())
  (for-each
    (lambda (file)
      (defvalues (status wall) (report-dispatched-file report file runtime-options))
      (set! outcomes (cons [file status wall] outcomes)))
    files)
  (def failed (map car (filter (lambda (row) (not (zero? (cadr row)))) (reverse outcomes))))
  (def elapsed (elapsed-milliseconds started))
  (call-with-output-file (path-expand "group.ss" report)
    (lambda (port)
      (write (list 'test-group-result group elapsed
               (map (lambda (key) (getenv key #f))
                    '("GITHUB_SHA" "GITHUB_RUN_ID" "GITHUB_RUN_ATTEMPT" "RUNNER_OS" "RUNNER_ARCH"))
               (reverse outcomes)) port)
      (newline port)))
  (displayln "TEST-GROUP-RESULT files=" (length files) " failed=" (length failed)
    " group-ms=" elapsed)
  (def slowest (list-sort (lambda (left right) (> (caddr left) (caddr right))) (reverse outcomes)))
  (for-each
    (lambda (row) (displayln "TEST-GROUP-SLOW " (car row) " dispatch-ms=" (caddr row)))
    (take slowest (min 5 (length slowest))))
  (for-each (lambda (file) (displayln "FAILED-TEST " file)) failed)
  (audit-report report group)
  (let (summary (getenv "GITHUB_STEP_SUMMARY" #f))
    (when summary
      (call-with-output-file (list path: summary append: #t)
        (lambda (port)
          (display (string-append "### Gerbil tests · " group "\n\n"
                                  (number->string (length files)) " files, "
                                  (number->string (length failed)) " failed.\n\n") port)
          (for-each (lambda (file) (display (string-append "- `" file "`\n") port)) failed)
          (newline port)))))
  (null? failed))

;; Measure the existing dispatch, including any special preparation selected
;; by Just. Assertions and Harness verdicts stay with the original worker.
(def (report-dispatched-file report file runtime-options)
  (def directory
    (parameterize ((current-temporary-directory report))
      (make-temporary-file-name "dispatch-")))
  (create-directory directory)
  (def raw (path-expand "worker.log" directory))
  (def started (current-jiffy))
  (def entry #f)
  (def harness-start #f)
  (def returned #f)
  (def module-line #f)
  (def harness-line #f)
  (def terminal? #f)
  (def phase #f)
  (def failure #f)
  (def last-progress #f)
  (def (observe line)
    (def progress? (string-prefix? "@yuanxu-progress " line))
    (cond (progress? (set! last-progress line))
          ((and (not entry) (string-prefix? "test-entry pid=" line))
           (set! entry (elapsed-milliseconds started)))
          ((and (not harness-start) (string-prefix? "HARNESS " line))
           (set! harness-start (elapsed-milliseconds started)))
          ((string-prefix? "MODULE-OK " line) (set! module-line line))
          ((string-prefix? "HARNESS-OK " line) (set! harness-line line))
          ((and harness-line (equal? line "OK\n"))
           (set! terminal? #t)
           (set! returned (elapsed-milliseconds started)))
          ((or (string-prefix? "declaration-stage " line)
               (string-prefix? "runtime-capacity-start " line)
               (string-prefix? "runtime-phase-incomplete " line))
           (set! phase line))
          ((and (not failure)
                (or (string-prefix? "ERROR CASE " line)
                    (string-prefix? "ERROR CHECK " line)
                    (string-prefix? "ERROR HARNESS " line)
                    (string-contains line "Heap overflow")
                    (string-contains line "Stack overflow")))
           (set! failure line)))
    (when (string-prefix? "ERROR HARNESS " line)
      (set! returned (elapsed-milliseconds started)))
    ;; Ops still writes every line to the worker transcript. Only the CI
    ;; presentation omits machine frames.
    (unless progress?
      (display line)
      (force-output)))
  (displayln "TEST-START " file)
  (force-output)
  (def prepared?
    (member file '("t/artifact-closure-test.ss" "t/mop-store-boundary-test.ss"
                   "t/source-admission-gateway-test.ss" "t/artifact-authority-test.ss"
                   "t/source-loader-authority-test.ss")))
  (def result
    (run-script
      (.cc ProcessScript.
        command: (if prepared? (list "just" "test-discovered-file" file)
                   (native-test-command runtime-options file))
        environment: (if prepared? (.o YUANXU_TEST_REPORT_DIR: directory)
                       (.cc (native-test-environment) 'YUANXU_TEST_REPORT_DIR directory))
        log: raw check-status: #f progress: (lambda () observe))))
  (def wall (elapsed-milliseconds started))
  (def status (.get result status))
  ;; Native gxtest may exit directly. Match its output and wait status to
  ;; the unique argv receipt written by the child before entering the CLI.
  (def evidence
    (match (read-harness-receipt directory)
      (['test-harness-start paths (? string? progress)]
       (and harness-start returned
            (file-exists? (path-expand (path-strip-directory progress) directory))
            ['test-harness-result paths
             (if (and (zero? status) terminal? (not failure)) 'passed 'failed)
             status (- returned harness-start) progress]))
      (else #f)))
  (def verified?
    (match evidence
      (['test-harness-result [path] 'passed 0 _ _]
       (and (expected-harness-file? file path)
            terminal? entry returned (not failure)
            (equal? module-line (string-append "MODULE-OK " path "\n"))
            (equal? harness-line
                    (string-append "HARNESS-OK " (object->string [path]) "\n"))))
      (else #f)))
  (def row
    (list 'test-dispatch-result file 'exit-status status 'wait-status (.get result wait-status)
          'dispatch-ms wall 'entry-ms entry 'harness-return-ms returned
          'verified? verified? 'last-phase phase 'log raw 'harness evidence))
  (call-with-output-file (path-expand "dispatch.ss" directory)
    (lambda (port) (write row port) (newline port)))
  (display "TEST-DISPATCH-RESULT ") (write row) (newline) (force-output)
  (unless (and (zero? status) verified?)
    (display "TEST-REPORT-FAIL ")
    (write [file status (or failure (if (zero? status) 'missing-harness-verdict 'worker-nonzero))
            (or (last-harness-progress directory) last-progress)])
    (newline))
  (values (if (and (zero? status) (not verified?)) 1 status) wall))

(def (native-test-command runtime-options file)
  (list "env" "-u" "SDKROOT" "timeout" "--signal=TERM" "--kill-after=5s"
        (string-append (number->string test-worker-seconds) "s")
        "gxi" runtime-options "dev/test-file.ss" file))

(def (native-test-environment (overlay #f))
  (def prefix (getenv "GERBIL_PATH"))
  (def search (getenv "GERBIL_LOADPATH" ""))
  (.o GERBIL_LOADPATH:
      (string-join
        (filter (lambda (path) (and path (not (string-empty? path))))
          (list (path-expand "test-lib" prefix) overlay search
                (path-expand "lib" prefix) (current-directory))) ":")
      PATH: (string-append (path-expand "bin" prefix) ":" (getenv "PATH"))))

(def (last-harness-progress directory)
  (match (filter (lambda (name) (string-suffix? ".progress" name)) (directory-files directory))
    ([progress]
     (call-with-input-file (path-expand progress directory)
       (lambda (port)
         (let loop ((latest #f))
           (let (line (read-line port))
             (cond ((eof-object? line) latest)
                   ((string-prefix? "@yuanxu-progress " line) (loop line))
                   (else (loop latest))))))))
    (else #f)))

(def (expected-harness-file? discovered actual)
  (case (string->symbol discovered)
    ((t/mop-store-boundary-test.ss)
     (equal? actual "t/qualification/mop-state/store-boundary-driver.ss"))
    ((t/source-admission-gateway-test.ss)
     (and (string-prefix? "/" actual)
          (string-suffix? (string-append "/source/yuanxu/" discovered) actual)))
    (else (equal? discovered actual))))

;; Audit extracted artifacts without executing the data or a test worker.
(def (read-receipt path)
  (call-with-input-file path
    (lambda (port)
      (def value (read port))
      (unless (eof-object? (read port)) (error "multiple report records" path))
      value)))

(def (read-harness-receipt directory)
  (def receipts
    (filter (lambda (name) (and (string-suffix? ".ss" name)
                                (not (equal? name "dispatch.ss"))))
            (directory-files directory)))
  (and (pair? receipts) (null? (cdr receipts))
       (read-receipt (path-expand (car receipts) directory))))

(def (audit-dispatch directory)
  (def path (path-expand "dispatch.ss" directory))
  (match (read-receipt path)
    (['test-dispatch-result (? string? file) 'exit-status (? exact-integer? status)
      'wait-status (? exact-integer?) 'dispatch-ms (? exact-integer? wall)
      'entry-ms entry 'harness-return-ms returned 'verified? (? boolean? verified?)
      'last-phase _ 'log _ 'harness evidence]
     (unless (and (<= 0 status 255) (>= wall 0)
                  (or (not entry) (and (exact-integer? entry) (<= 0 entry wall)))
                  (or (not returned)
                      (and entry (exact-integer? returned) (<= entry returned wall)))
                  (file-exists? (path-expand "worker.log" directory)))
       (error "invalid worker timing or missing transcript" path))
     (when verified?
       (unless (match evidence
                 (['test-harness-result [actual] 'passed 0 _ _]
                  (and entry returned (expected-harness-file? file actual)))
                 (else #f))
         (error "verified dispatch has no matching Harness evidence" path)))
     (def effective-status (if (and (zero? status) (not verified?)) 1 status))
     (def harness-ms
       (match evidence
         (['test-harness-result paths verdict native-status (? exact-integer? elapsed) (? string? progress)]
          (unless (and returned (<= 0 elapsed (- returned entry))
                       (eqv? status native-status)
                       (memq verdict '(passed failed))
                       (equal? ['test-harness-start paths progress]
                               (read-harness-receipt directory))
                       (file-exists? (path-expand (path-strip-directory progress) directory)))
            (error "dispatch does not match the retained Harness receipt" path))
          elapsed)
         (#f #f)
         (else (error "malformed Harness evidence" path))))
     [file effective-status wall status entry harness-ms (and returned (- wall returned))])
    (else (error "malformed dispatch receipt" path))))

(def (audit-group directory)
  (def report
    (if (file-exists? (path-expand "group.ss" directory)) directory
      (path-expand "test-report" directory)))
  (match (read-receipt (path-expand "group.ss" report))
    (['test-group-result (? string? group) (? exact-integer? elapsed) cohort rows]
     (def expected (discovered-files group))
     (def qualification (read-receipt (path-expand "qualification.ss" report)))
     (def actual
       (filter-map
         (lambda (name)
           (and (string-prefix? "dispatch-" name)
                (audit-dispatch (path-expand name report))))
         (directory-files report)))
     (def (order rows)
       (list-sort (lambda (left right) (string<? (car left) (car right))) rows))
     (unless (and (list? cohort) (= (length cohort) 5)
                  (pair? qualification) (eq? (car qualification) 'test-qualification)
                  (andmap (lambda (field) (or (not field) (string? field))) cohort)
                  (pair? expected) (equal? expected (read-receipt (path-expand "expected-files.ss" report)))
                  (equal? expected (map car rows)) (equal? (order rows) (order (map (cut take <> 3) actual)))
                  (>= elapsed (apply + (map caddr rows))))
       (error "incomplete or inconsistent test group coverage" group report))
     (values cohort actual qualification))
    (else (error "malformed test group receipt" report))))

(def (read-audited-report root group)
  (def nested (path-expand "test-report" root))
  (def report (if (file-exists? nested) nested root))
  (def folders
    (if (file-exists? (path-expand "group.ss" report))
      [report] (map (cut path-expand <> report) (directory-files report))))
  (def cohort #f)
  (def qualification #f)
  (def rows '())
  (for-each
    (lambda (folder)
      (defvalues (identity results environment) (audit-group folder))
      (when (and cohort (not (and (equal? identity cohort) (equal? environment qualification))))
        (error "test reports mix CI runs, revisions, or platforms" folder))
      (set! cohort identity)
      (set! qualification environment)
      (set! rows (append results rows)))
    folders)
  (def ordered (list-sort (lambda (left right) (string<? (car left) (car right))) rows))
  (unless (and (pair? ordered) (equal? (map car ordered) (discovered-files group)))
    (error "incomplete or duplicate coverage across test groups" root group))
  (values cohort ordered qualification))

(def (audit-report root (group "all"))
  (defvalues (cohort rows _qualification) (read-audited-report root group))
  (display "TEST-REPORT-AUDIT ")
  (write [group cohort (length rows)
           (length (filter (lambda (row) (not (zero? (cadr row)))) rows))])
  (newline))

(def (write-platform-totals platform rows)
  (def (phase index)
    (def observed (filter-map (cut list-ref <> index) rows))
    [(apply + observed) (- (length rows) (length observed))])
  (display "TEST-TIMING-TOTAL ")
  (write [platform 'dispatch-ms (apply + (map caddr rows))
          'startup (phase 4) 'harness (phase 5) 'after-harness (phase 6)])
  (newline))

(def (compare-reports linux macos (group "all"))
  (defvalues (linux-cohort linux-rows linux-qualification) (read-audited-report linux group))
  (defvalues (macos-cohort macos-rows macos-qualification) (read-audited-report macos group))
  (unless (and (qualification-build-matches? linux-qualification)
               (qualification-build-matches? macos-qualification)
               (andmap (lambda (key)
                         (let (left (qualification-field linux-qualification key))
                           (and left (equal? left (qualification-field macos-qualification key)))))
                       '(source package-declaration gerbil gambit just poo
                         runtime-options idle-seconds worker-seconds)))
    (error "platform reports have different source or test qualification inputs"))
  (unless (match [linux-cohort macos-cohort]
            ([[sha run attempt "Linux" linux-arch] [other-sha other-run other-attempt "macOS" macos-arch]]
             (and (andmap (lambda (value) (and (string? value) (not (string-empty? value))))
                          [sha run attempt linux-arch macos-arch])
                  (equal? [sha run attempt] [other-sha other-run other-attempt])))
            (else #f))
    (error "platform reports must be Linux and macOS from the same CI execution" linux-cohort macos-cohort))
  (display "TEST-TIMING-COHORT ")
  (write [group linux-cohort macos-cohort (length linux-rows)])
  (newline)
  (displayln "TEST-TIMING-PHASE-TOTALS (observed-ms missing-files)")
  (write-platform-totals "Linux" linux-rows)
  (write-platform-totals "macOS" macos-rows)
  (displayln "TEST-TIMING-FIELDS (group-status dispatch-ms worker-exit-status startup-ms harness-ms after-harness-ms)")
  (for-each
    (lambda (linux-row macos-row)
      (display "TEST-TIMING ")
      (write [(car linux-row) (cdr linux-row) (cdr macos-row)])
      (newline))
    linux-rows macos-rows))

(def input-order-test "t/build-input-context-test.ss")
(def input-admission-test "t/module-build-role-test.ss")
(def input-partition
  "(def inputs (append (filter (lambda (path) (not (output? path))) previous)\n                     (filter output? previous)))")
(def build-input-mutations
  [["output-first" input-partition
    "(def inputs (append (filter output? previous)\n                     (filter (lambda (path) (not (output? path))) previous)))"
    input-order-test "ERROR CHECK (load-path)"]
   ["reversed-prerequisites" input-partition
    "(def inputs (append (reverse (filter (lambda (path) (not (output? path))) previous))\n                     (filter output? previous)))"
    input-order-test "ERROR CHECK (load-path)"]
   ["missing-restoration" "(set-load-path! previous)" "(void)"
    input-order-test "ERROR CHECK (load-path)"]
   ["accepted-input-mutation" "(unless unchanged? (refuse))" "(void)"
    input-admission-test "--- irritants: changed-compiler-input-refused"]])

(def (verify-build-input-mutations directory runtime-options)
  (def source "module-system/building/source-package.ss")
  (def (source-bytes file) (call-with-input-file file read-all-as-u8vector))
  (def original (source-bytes source))
  (def text (utf8->string original))
  (create-directory* directory)
  (def report
    (parameterize ((current-temporary-directory (path-expand directory)))
      (make-temporary-file-name "build-input-context-")))
  (create-directory report)
  (displayln "BUILD-INPUT-CONTEXT-ARTIFACTS " report) (force-output)
  (def receipt (make-hash-table))
  (hash-put! receipt "source_sha256" (hex-encode (sha256 original)))
  (def runs '())
  (def (invoke label command (environment (.o)))
    (def log (path-expand (string-append label ".log") report))
    (def result (run-script (.cc ProcessScript. command: command environment: environment
                                log: log check-status: #f)))
    (def status (.get result status))
    (set! runs (cons (list->hash-table [(cons "label" label) (cons "exit" status)]) runs))
    (values status (call-with-input-file log read-all-as-string)))
  (def (positive label file)
    (defvalues (status output) (invoke label (native-test-command runtime-options file) (native-test-environment)))
    (unless (and (zero? status)
                 (string-contains output "MODULE-OK ") (string-contains output "HARNESS-OK ")
                 (member "OK" (string-split output #\newline))
                 (not (ormap (lambda (marker) (string-contains output marker))
                             '("ERROR CASE" "ERROR CHECK" "ERROR HARNESS" "Heap overflow" "Stack overflow"))))
      (error "correct implementation failed" label report))
    (displayln "BUILD-INPUT-CONTEXT-PASS " label) (force-output))
  (def (mutate row)
    (match row ([name old replacement file expected]
      (def offset (string-contains text old))
      (def end (and offset (+ offset (string-length old))))
      (unless (and end (or (equal? name "missing-restoration")
                          (not (string-contains (substring text end (string-length text)) old))))
        (error "mutation anchor changed" name))
      (def root (path-expand name report))
      (def path (path-expand "source-package.ss" root))
      (def library (path-expand "lib" root))
      (create-directory* library)
      (call-with-output-file path
        (lambda (port)
          (display "package: yuanxu/module-system/building\n" port)
          (display (substring text 0 offset) port)
          (display replacement port)
          (display (substring text end (string-length text)) port)))
      (def variant (list->hash-table [(cons "source_sha256" (hex-encode (sha256 (source-bytes path))))
                                     (cons "test" file)]))
      (hash-put! receipt name variant)
      (defvalues (compiled _)
        (invoke (string-append name "-compile")
          (list "timeout" "--signal=TERM" "--kill-after=5s" "120s" "gxc"
                runtime-options "-O" "-d" library path)))
      (unless (zero? compiled) (error "mutation did not compile" name report))
      (defvalues (status output)
        (invoke name (native-test-command runtime-options file) (native-test-environment library)))
      (unless (and (= status 42) (string-contains output expected)
                   (not (string-contains output "Heap overflow"))
                   (not (string-contains output "Stack overflow")))
        (error "mutation survived or failed for the wrong reason" name status report))
      (hash-put! variant "rejected" #t)
      (displayln "BUILD-INPUT-CONTEXT-REJECTED " name " exit=" status) (force-output))))
  (dynamic-wind void
    (lambda ()
      (positive "before-order" input-order-test)
      (positive "before-admission" input-admission-test)
      (for-each mutate build-input-mutations)
      (positive "after-order" input-order-test)
      (positive "after-admission" input-admission-test)
      (hash-put! receipt "ok" #t))
    (lambda ()
      (def unchanged? (equal? original (source-bytes source)))
      (hash-put! receipt "source_unchanged" unchanged?)
      (hash-put! receipt "runs" (list->vector (reverse runs)))
      (call-with-output-file (path-expand "receipt.json" report)
        (lambda (port) (display (json->string receipt) port) (newline port)))
      (unless unchanged? (error "checkout source changed during mutation qualification"))))
  (displayln "BUILD-INPUT-CONTEXT-MUTATIONS-OK mutations=4 source-unchanged=true"))
