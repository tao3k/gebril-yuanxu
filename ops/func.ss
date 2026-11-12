;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object "./types.ss"
        (only-in "./progress.ss" call-with-execution-watchdog copy-process-output)
        (only-in :clan/poo/mop validate)
        (only-in :std/misc/process run-process)
        (only-in :std/os/signal kill SIGKILL SIGTERM)
        (only-in :std/os/signal-handler add-signal-handler! remove-signal-handler!)
        (only-in :std/os/error os-error? OSError-errno ESRCH)
        (only-in :std/misc/ports read-all-as-string))
(export validate-script prepare-script-command merge-script-environment preview-script
        run-script call-with-script-coprocess run-script-batch
        call-with-execution-cancellation)

;; A TERM from the enclosing process budget must unwind the resource owner,
;; not just stop its child. Register lazily around effects/fixtures. Nested
;; operations on the same thread share one registration; no resource is held
;; after that dynamic extent. SIGKILL cannot run Scheme cleanup.
(def cancellation-owner (make-parameter #f))
(def cancellation-lock (make-mutex 'execution-cancellation))
(def cancellation-owners '())
(def (with-cancellation-lock thunk)
  (dynamic-wind
    (lambda () (mutex-lock! cancellation-lock)) thunk
    (lambda () (mutex-unlock! cancellation-lock))))
(def (interrupt-execution! thread action)
  (with-catch
    (lambda (cause)
      (unless (or (inactive-thread-exception? cause) (abandoned-mutex-exception? cause))
        (raise cause)))
    (lambda () (thread-interrupt! thread action))))
(def (cancel-executions!)
  (def owners
    (with-cancellation-lock
      (lambda ()
        (filter-map
          (lambda (entry)
            (and (not (vector-ref entry 2))
                 (begin (vector-set! entry 2 #t) entry)))
          cancellation-owners))))
  ;; Never interrupt while holding the registry lock: unwinding unregisters.
  (for-each
    (lambda (entry)
      (interrupt-execution! (vector-ref entry 0)
        (lambda ()
          (when (vector-ref entry 1)
            (error "Ops execution terminated" SIGTERM)))))
    owners))
(def (call-with-execution-cancellation thunk)
  (def owner (current-thread))
  (if (eq? owner (cancellation-owner)) (thunk)
    (let (entry (vector owner #t #f))
      (dynamic-wind
        (lambda ()
          (with-cancellation-lock
            (lambda ()
              (vector-set! entry 1 #t)
              (when (null? cancellation-owners)
                (add-signal-handler! SIGTERM cancel-executions!))
              (set! cancellation-owners (cons entry cancellation-owners)))))
        (lambda () (parameterize ((cancellation-owner owner)) (thunk)))
        (lambda ()
          (with-cancellation-lock
            (lambda ()
              (vector-set! entry 1 #f)
              (set! cancellation-owners (remq entry cancellation-owners))
              (when (null? cancellation-owners)
                (remove-signal-handler! SIGTERM)))))))))

;; The enclosing owner must interrupt and join these children on unwind.
;; Only that owner receives SIGTERM, so a child cannot start more work
;; between its own signal and the owner's cancellation.
(def (make-execution-child thunk)
  (unless (eq? (cancellation-owner) (current-thread))
    (error "Ops child requires an active cancellation owner"))
  (make-thread
    (lambda ()
      (parameterize ((cancellation-owner (current-thread))) (thunk)))))

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
      (append (list (or (and (.slot? script 'timeout-program) (.get script timeout-program)) "timeout") "--verbose" "--signal=TERM" "--kill-after=5s"
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

;; Runtime adaptation is private. Sample ambient state only during execution.
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
(def (execute-script prepared environment forward exchange)
  (let* ((started (real-time)) (exit-status #f)
         (captured-output
          (run-process (.get prepared argv)
            directory: (.get prepared directory)
            environment: environment
            stdin-redirection: (and exchange #t) stderr-redirection: (.get prepared stderr-redirection)
            check-status: (lambda (code _settings) (set! exit-status code))
            coprocess: (lambda (process)
                        (def completed? #f)
                        (dynamic-wind void
                          (lambda ()
                            (begin0
                              (cond
                               (exchange
                                (begin0 (exchange process)
                                  (close-output-port process)
                                  (unless (zero? (read-subu8vector (make-u8vector 1) 0 1 process))
                                    (error "unexpected Ops output after process exchange"))
                                  ;; EOF can precede process exit. Wait while
                                  ;; unwind still owns process-group cancellation.
                                  (process-status process)))
                               ((.get prepared log)
                                (call-with-output-file (list path: (.get prepared log) truncate: #t)
                                  (lambda (port)
                                    (copy-process-output process port
                                      (and (.get prepared progress) ((.get prepared progress))) forward))))
                               (else
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
                                          (and (.get prepared progress) ((.get prepared progress))) forward)))))))
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
      ;; A failed child may have completed Cases before failing during native
      ;; shutdown. Expose the exit status and transcript location before raising
      ;; the original error, whose irritants still retain the complete output.
      ;; Do not duplicate arbitrary child output into the enclosing Harness.
      (let (diagnostics (current-error-port))
        (display "Ops child exit-status=" diagnostics)
        (display (process-exit-code exit-status) diagnostics)
        (display " log=" diagnostics)
        (write (.get prepared log) diagnostics)
        (newline diagnostics)
        (force-output diagnostics))
      (error "Ops script failed" (process-exit-code exit-status)
             (.get prepared log) (if exchange "" captured-output)))
    (if exchange captured-output
      (.o status: (process-exit-code exit-status) wait-status: exit-status seconds: elapsed-value
          output: captured-output log: (.get prepared log)))))
(def (run-script script (arguments '()) stderr-redirection: (stderr-value #t)
                output-port: (forward #f))
  (unless (or (not forward) (output-port? forward))
    (error "Ops forwarding requires an output port"))
  (run-owned-script script arguments stderr-value forward #f))

;; Scheduling owns only workers and declaration order. run-script still owns
;; every child, including its output, watchdog and process-group unwind.
(def (run-script-batch batch)
  (def checked (validate ScriptBatchContract batch))
  (def scripts (list->vector (.get checked scripts)))
  (def size (vector-length scripts))
  (def results (make-vector size))
  (def lock (make-mutex 'ops-script-batch))
  (def stop (gensym 'ops-script-batch-cancelled))
  (def next 0)
  (def stopped? #f)
  (def workers '())
  (def joined? #f)
  (def cleanup-errors '())
  (def (claim!)
    (with-dynamic-lock lock
      (lambda ()
        (and (not stopped?) (< next size)
             (begin0 next (set! next (1+ next)))))))
  (def (worker)
    (with-catch (lambda (cause) (unless (eq? cause stop) (raise cause)))
      (lambda ()
        (let loop ()
          (let (index (claim!))
            (when index
              (vector-set! results index
                (with-catch
                  (lambda (cause)
                    (if (eq? cause stop) (raise cause)
                      (.o ok?: #f receipt: #f failure: cause)))
                  (lambda ()
                    (def completed (run-script (vector-ref scripts index)))
                    (.o ok?: #t receipt: completed failure: #f))))
              (loop)))))))
  (def (cancel!)
    (with-dynamic-lock lock (lambda () (set! stopped? #t)))
    (def started
      (filter (lambda (thread) (not (thread-state-initialized? (thread-state thread)))) workers))
    (for-each
      (lambda (thread)
        (with-catch
          (lambda (cause) (set! cleanup-errors (cons cause cleanup-errors)))
          (lambda () (interrupt-execution! thread (lambda () (raise stop))))))
      started)
    (for-each
      (lambda (thread)
        (with-catch
          (lambda (cause)
            (unless (and (uncaught-exception? cause) (eq? (uncaught-exception-reason cause) stop))
              (set! cleanup-errors (cons cause cleanup-errors))))
          (lambda () (thread-join! thread))))
      started))
  (call-with-execution-cancellation
    (lambda ()
      (with-catch
        (lambda (cause)
          (if (null? cleanup-errors) (raise cause)
            (error "Ops batch and worker cleanup failed" cause (reverse cleanup-errors))))
        (lambda ()
          (dynamic-wind void
            (lambda ()
              (let start ((remaining (min size (.get checked concurrency))))
                (unless (zero? remaining)
                  (let (thread (make-execution-child worker))
                    (set! workers (cons thread workers))
                    (thread-start! thread)
                    (start (1- remaining)))))
              (for-each thread-join! workers)
              (set! joined? #t)
              (vector->list results))
            (lambda () (unless joined? (cancel!)))))))))

(def (call-with-script-coprocess script exchange)
  (unless (procedure? exchange)
    (error "Ops exchange requires a procedure"))
  (run-owned-script script '() #f #f exchange))

(def (run-owned-script script arguments stderr-value forward exchange)
  ;; Validation precedes ambient sampling. The same preparation feeds execution.
  (let* ((prepared (preview-script script arguments stderr-redirection: stderr-value))
         (overrides (.get prepared environment))
         ;; Without overrides, let std/run-process inherit the environment.
         ;; An explicit environment is only needed for a real overlay.
         (environment
          (and (pair? (.all-slots overrides))
               (process-environment
                 (merge-script-environment (inherited-process-environment) overrides)))))
    (when (and exchange (or (.get prepared log) (.get prepared progress)
                            (not (.get prepared timeout)) (not (.get prepared check-status))))
      (error "Ops exchange requires a supervised, checked process with a separate stdout stream"))
    (let (execute (lambda () (execute-script prepared environment forward exchange)))
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
