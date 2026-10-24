;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "./types.ss"
        (only-in "./progress.ss" call-with-execution-watchdog call-with-execution-cancellation
                 copy-process-output)
        (only-in :clan/poo/mop validate)
        (only-in :std/misc/process run-process)
        (only-in :std/os/signal kill SIGKILL)
        (only-in :std/os/error os-error? OSError-errno ESRCH)
        (only-in :std/misc/ports read-all-as-string))
(export validate-script prepare-script-command merge-script-environment preview-script run-script)

;; Pure APIs: explicit inert inputs, no environment lookup, clock, files or spawn.
(def (validate-script script)
  (validate ProcessScriptContract script))
(def (prepare-script-command script (arguments '()))
  (script-command (validate-script script) arguments))
(def (script-command script arguments)
  (unless (and (list? arguments) (every string? arguments))
    (error "Ops arguments must be strings"))
  (let (argv (append (.get script command) arguments))
    (if (.get script timeout)
      ;; Preserve the watchdog's own signal report in failed Ops output. A 137
      ;; alone cannot distinguish deadline escalation from another SIGKILL.
      ;; Batch jobs need descendant signaling, not terminal foreground mode.
      (append (list "timeout" "--verbose" "--signal=TERM" "--kill-after=5s"
                    (string-append (number->string (.get script timeout)) "s")) argv)
      argv)))
(def (merge-script-environment inherited overrides)
  (for-each
    (lambda (value)
      (validate OpsEnvironmentContract value))
    (list inherited overrides))
  (.+ inherited overrides))
(def (preview-script script (arguments '()) (inherited-environment (.o))
                     stderr-redirection: (stderr-value #t))
  (unless (boolean? stderr-value) (error "Ops stderr-redirection must be boolean"))
  (let* ((script (validate-script script))
         (argv-value (script-command script arguments))
        (environment-value (merge-script-environment inherited-environment (.get script environment))))
    (.o argv: argv-value directory: (.get script directory)
        environment: environment-value timeout: (.get script timeout)
        idle-timeout: (and (.slot? script 'idle-timeout) (.get script idle-timeout))
        progress: (and (.slot? script 'progress) (.get script progress))
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
(def (process-exit-code wait-status)
  (if (zero? (bitwise-and wait-status #xff))
    (arithmetic-shift wait-status -8)
    (+ 128 (bitwise-and wait-status #x7f))))
(def (execute-script prepared forward)
  (let* ((started (real-time)) (exit-status #f)
         (captured-output
          (run-process (.get prepared argv)
            directory: (.get prepared directory)
            environment: (process-environment (.get prepared environment))
            stdin-redirection: #f stderr-redirection: (.get prepared stderr-redirection)
            check-status: (lambda (code _settings) (set! exit-status code))
            coprocess: (lambda (process)
                        (def completed? #f)
                        (dynamic-wind void
                          (lambda ()
                            (begin0
                              (if (.get prepared log)
                                (call-with-output-file (list path: (.get prepared log) truncate: #t)
                                  (lambda (port)
                                    (copy-process-output process port
                                      (and (.get prepared progress) ((.get prepared progress))) forward)))
                                (call-with-output-string
                                  (lambda (port)
                                    (with-catch
                                      (lambda (failure)
                                        ;; Preserve the actual partial child transcript on
                                        ;; cancellation; rethrow the SAME original cause.
                                        (display (get-output-string port) (current-error-port))
                                        (force-output (current-error-port))
                                        (raise failure))
                                      (lambda ()
                                        (copy-process-output process port
                                          (and (.get prepared progress) ((.get prepared progress))) forward))))))
                              (set! completed? #t)))
                          (lambda ()
                            ;; std/run-process closes and waits on unwind; it
                            ;; does not terminate a child interrupted by a Case.
                            ;; timeout owns a dedicated group in batch mode.
                            (unless completed?
                              (with-catch
                                (lambda (failure)
                                  (unless (and (os-error? failure)
                                               (= (OSError-errno failure) ESRCH))
                                    (raise failure)))
                                (lambda ()
                                  (kill (if (.get prepared timeout)
                                          (- (process-pid process)) (process-pid process))
                                        SIGKILL)))))))))
         (elapsed-value (- (real-time) started)))
    (when (and (.get prepared check-status) (not (zero? exit-status)))
      (error "Ops script failed" (process-exit-code exit-status)
             (.get prepared log) captured-output))
    (.o status: (process-exit-code exit-status) wait-status: exit-status seconds: elapsed-value
        output: captured-output log: (.get prepared log))))
(def (run-script script (arguments '()) stderr-redirection: (stderr-value #t)
                output-port: (forward #f))
  (unless (or (not forward) (output-port? forward))
    (error "Ops forwarding requires an output port"))
  ;; Validation precedes ambient sampling. The same preparation feeds execution.
  (let* ((prepared (preview-script script arguments stderr-redirection: stderr-value))
         (environment-value
          (merge-script-environment (inherited-process-environment) (.get prepared environment))))
    (let (execute (lambda () (execute-script (.cc prepared 'environment environment-value) forward)))
      (call-with-execution-cancellation
        (lambda ()
          (if (.get prepared idle-timeout)
            (call-with-execution-watchdog
              (* 1000 (.get prepared idle-timeout))
              ;; GNU timeout owns the existing total-budget exit status (124).
              ;; Do not race it with a second total exception, especially when
              ;; check-status is false and callers explicitly inspect the receipt.
              #f execute)
            (execute)))))))
