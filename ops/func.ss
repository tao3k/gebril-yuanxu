;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "./types.ss"
        (only-in :core/types poo-flow-validation-evidence-accepted?)
        (only-in :std/misc/process run-process)
        (only-in :std/misc/ports read-all-as-string))
(export validate-script prepare-script-command merge-script-environment preview-script run-script)

;; Pure APIs: explicit inert inputs, no environment lookup, clock, files or spawn.
(def (validate-script script)
  (unless (poo-flow-validation-evidence-accepted?
            (.call ProcessScriptContract .admit script #f))
    (error "invalid Ops process declaration"))
  script)
(def (prepare-script-command script (arguments '()))
  (validate-script script)
  (unless (and (list? arguments) (every string? arguments))
    (error "Ops arguments must be strings"))
  (let (argv (append (.get script command) arguments))
    (if (.get script timeout)
      (append (list "timeout" "--foreground" "--signal=TERM" "--kill-after=5s"
                    (string-append (number->string (.get script timeout)) "s")) argv)
      argv)))
(def (merge-script-environment inherited overrides)
  (for-each
    (lambda (value)
      (unless (poo-flow-validation-evidence-accepted?
                (.call OpsEnvironmentContract .admit value #f))
        (error "invalid Ops environment")))
    (list inherited overrides))
  (.+ inherited overrides))
(def (preview-script script (arguments '()) (inherited-environment (.o))
                     stderr-redirection: (stderr-value #t))
  (unless (boolean? stderr-value) (error "Ops stderr-redirection must be boolean"))
  (let* ((argv-value (prepare-script-command script arguments))
        (environment-value (merge-script-environment inherited-environment (.get script environment))))
    (.o argv: argv-value directory: (.get script directory)
        environment: environment-value timeout: (.get script timeout)
        log: (.get script log) check-status: (.get script check-status)
        stderr-redirection: stderr-value)))

;; Runtime adaptation is private. Ambient state is sampled only by run-script.
(def (process-environment value)
  (map (lambda (key) (string-append (symbol->string key) "=" (.ref value key)))
       (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
                  (.all-slots value))))
(def (inherited-process-environment)
  (object<-alist
    (map (lambda (entry) (cons (string->symbol (car entry)) (cdr entry)))
         (get-environment-variables))))
(def (copy-process-output process port)
  (close-output-port process)
  (let loop ((line (read-line process)))
    (unless (eof-object? line)
      (display line port) (newline port) (force-output port) (loop (read-line process)))))
(def (process-exit-code wait-status)
  (if (zero? (bitwise-and wait-status #xff))
    (arithmetic-shift wait-status -8)
    (+ 128 (bitwise-and wait-status #x7f))))
(def (execute-script prepared)
  (let* ((started (real-time)) (exit-status #f)
         (captured-output
          (run-process (.get prepared argv)
            directory: (.get prepared directory)
            environment: (process-environment (.get prepared environment))
            stdin-redirection: #f stderr-redirection: (.get prepared stderr-redirection)
            check-status: (lambda (code _settings) (set! exit-status code))
            coprocess: (lambda (process)
                        (if (.get prepared log)
                          (call-with-output-file (list path: (.get prepared log) truncate: #t)
                            (cut copy-process-output process <>))
                          (read-all-as-string process)))))
         (elapsed-value (- (real-time) started)))
    (when (and (.get prepared check-status) (not (zero? exit-status)))
      (error "Ops script failed" (process-exit-code exit-status)
             (.get prepared log) captured-output))
    (.o status: (process-exit-code exit-status) wait-status: exit-status seconds: elapsed-value
        output: captured-output log: (.get prepared log))))
(def (run-script script (arguments '()) stderr-redirection: (stderr-value #t))
  ;; Validation precedes ambient sampling. The same preparation feeds execution.
  (let* ((prepared (preview-script script arguments stderr-redirection: stderr-value))
         (environment-value
          (merge-script-environment (inherited-process-environment) (.get prepared environment))))
    (execute-script (.cc prepared 'environment environment-value))))
