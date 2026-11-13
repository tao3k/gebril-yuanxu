;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Fault fixtures for the standard std/test suite, not an executable runner.
(import (only-in :clan/poo/object .o .cc .get)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/encoding/json json->string)
        (only-in :std/io/tempfile make-temporary-file-name current-temporary-directory)
        (only-in :std/misc/ports read-all-as-string read-all-as-u8vector)
        (only-in :tao3k/yuanxu/ops/func run-script)
        (only-in :tao3k/yuanxu/ops/process-script ProcessScript.))
(export verify-build-input-mutations)

(def (gerbil-test-arguments runtime-options file)
  (list "env" "-u" "SDKROOT" "timeout" "--signal=TERM" "--kill-after=5s"
        "600s" "gerbil" runtime-options "test" file))

(def (gerbil-test-environment (overlay #f))
  (def prefix (getenv "GERBIL_PATH"))
  (def search (getenv "GERBIL_LOADPATH" ""))
  (.o GERBIL_LOADPATH:
      (string-join
        (filter (lambda (path) (and path (not (string-empty? path))))
          (list overlay search
                (path-expand "lib" prefix) (current-directory))) ":")
      PATH: (string-append (path-expand "bin" prefix) ":" (getenv "PATH"))))

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
    (defvalues (status output) (invoke label (gerbil-test-arguments runtime-options file) (gerbil-test-environment)))
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
          (display "package: tao3k/yuanxu/module-system/building\n" port)
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
        (invoke name (gerbil-test-arguments runtime-options file) (gerbil-test-environment library)))
      ;; Gerbil's tool dispatch can discard gxtest-main's returned status 42.
      ;; Require a completed, failing harness and the exact fault assertion.
      (def lines (string-split output #\newline))
      (unless (and (memv status '(0 42))
                   (member (string-append "MODULE-OK " file) lines)
                   (member (string-append "ERROR HARNESS (" file ")") lines)
                   (string-contains output expected)
                   (not (member "OK" lines))
                   (not (ormap (lambda (marker) (string-contains output marker))
                               '("Heap overflow" "Stack overflow"))))
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
