;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Execution liveness, not observation emission, admission or a result cache.
(import (only-in :std/encoding/json read-json write-json make-JSONReadOptions
                 current-json-read-options)
        (only-in :std/os/pid getpid)
        (only-in :std/os/signal SIGTERM)
        (only-in :std/os/signal-handler add-signal-handler! remove-signal-handler!))
(export execution-idle-seconds execution-total-seconds
        current-execution-progress call-with-execution-progress
        execution-progress! execution-progress-status execution-progress-idle-milliseconds
        execution-progress-limit
        call-with-execution-watchdog call-with-execution-cancellation
        make-nix-progress-reader make-test-progress-reader)

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
      (thread-interrupt! (vector-ref entry 0)
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

(def execution-idle-seconds 60)
(def execution-total-seconds 600)
(defstruct execution-progress (started last idle total counters sequence emitted scope clock))
(def current-execution-progress (make-parameter '()))
(def (milliseconds)
  (quotient (* (current-jiffy) 1000) (jiffies-per-second)))

;; Only bounded scalar progress metadata is retained. No source contexts,
;; objects, outputs or validation results become roots here.
(def (call-with-execution-progress idle total thunk clock: (clock milliseconds))
  (unless (and (or (not idle) (and (real? idle) (> idle 0) (< idle +inf.0)))
               (or (not total) (and (real? total) (> total 0) (< total +inf.0))))
    (error "invalid execution progress budget" idle total))
  (let* ((now (clock))
         (state (make-execution-progress now now idle total (make-hash-table)
                  0 now (string-append (number->string (getpid)) "/"
                            (symbol->string (gensym 'execution))) clock)))
    (parameterize ((current-execution-progress (cons state (current-execution-progress))))
      (thunk state))))
(def (execution-progress-idle-milliseconds state)
  (- ((execution-progress-clock state)) (execution-progress-last state)))
(def (execution-progress-limit state reason)
  (if (eq? reason 'idle) (execution-progress-idle state) (execution-progress-total state)))
(def (execution-progress-status state)
  (let (now ((execution-progress-clock state)))
    (cond ((and (execution-progress-total state)
                (>= (- now (execution-progress-started state)) (execution-progress-total state))) 'total)
          ((and (execution-progress-idle state)
                (>= (- now (execution-progress-last state)) (execution-progress-idle state))) 'idle)
          (else #f))))
(def (execution-progress! key count)
  (unless (and (exact-integer? count) (>= count 0))
    (error "execution progress requires a natural count"))
  (def advanced? #f)
  (for-each
    (lambda (state)
      (let* ((counts (execution-progress-counters state))
             (prior (or (hash-get counts key) 0)))
        (when (and (not (execution-progress-status state)) (> count prior)
                   (or (hash-key? counts key) (< (hash-length counts) 4096)))
          (hash-put! counts key count)
          (execution-progress-last-set! state ((execution-progress-clock state)))
          (execution-progress-sequence-set! state (+ 1 (execution-progress-sequence state)))
          (set! advanced? #t))))
    (current-execution-progress))
  ;; Relay genuine progress to the supervising Ops process, at most once per
  ;; second. Nothing emits merely because a timer fired. Replays are inert.
  (when (and advanced? (pair? (current-execution-progress)))
    (let* ((state (car (reverse (current-execution-progress))))
           (now ((execution-progress-clock state))))
      (when (>= (- now (execution-progress-emitted state)) 1000)
        (execution-progress-emitted-set! state now)
        (let (line (call-with-output-string
                     (lambda (port)
                       ;; A preceding command may have emitted an unterminated
                       ;; stdout fragment; protocol records need their own line.
                       (newline port)
                       (display "@poo-progress " port)
                       (write-json port (vector (execution-progress-scope state)
                                                (execution-progress-sequence state)))
                       (newline port))))
          (display line (current-error-port)) (force-output (current-error-port))))))
  advanced?)

;; Ops and the Case memory sampler share this state. Ops needs a sampler only
;; when it owns an external effect; std/run-process still owns spawn/wait.
(def (call-with-execution-watchdog idle total thunk)
  (call-with-execution-progress idle total
    (lambda (state)
      (def owner (current-thread))
      (def done? #f)
      (def sampler
        (make-thread
          (lambda ()
            (let loop ()
              (thread-sleep! 0.01)
              (unless done?
                (let (reason (execution-progress-status state))
                  (if reason
                    (begin
                      (set! done? #t)
                      (thread-interrupt! owner
                        (lambda () (error "Ops execution budget exceeded" reason))))
                    (loop))))))))
      (thread-start! sampler)
      (dynamic-wind void thunk
        ;; An interrupting sampler can be waiting for this thread's handler;
        ;; joining it here would deadlock unwinding. Match the Case watchdog.
        (lambda () (set! done? #t) (thread-terminate! sampler))))))

(def (json-record line prefix)
  (and (<= (string-length line) 65536) (string-prefix? prefix line)
       (with-catch (lambda (_) #f)
         (lambda ()
           (parameterize ((current-json-read-options
                            (make-JSONReadOptions key-as-symbol: #t
                              object-as-hash: #t array-as-vector: #t)))
             (call-with-input-string
               (substring line (string-length prefix) (string-length line)) read-json))))))
(def (field record name)
  (and (hash-table? record) (hash-get record name)))
(def (make-nix-progress-reader observe: (observe #f))
  (unless (or (not observe) (procedure? observe))
    (error "Nix observation must be a procedure or false"))
  (def activities (make-hash-table))
  (lambda (line)
    (let* (;; Native diagnostic messages cannot advance liveness. A parent
           ;; test already receives the child's progress relay; do not decode
           ;; thousands of diagnostic JSON records there a second time. Keep
           ;; the general decoder for other serializations and activity events.
           (record (and (or observe
                            (not (string-prefix? "@nix {\"action\":\"msg\"," line)))
                        (json-record line "@nix ")))
           (action (field record 'action)) (id (field record 'id))
           (kind (field record 'type)) (fields (field record 'fields)))
      ;; Reuse THIS decode for observation; observers cannot grant progress.
      (when (and observe (hash-table? record)) (observe record))
      (when (and (exact-integer? id) (>= id 0))
        (cond
         ((and (equal? action "start") (memv kind '(100 101 102 103 104 105 108 109 110 112))
               (< (hash-length activities) 4096))
          ;; Starting an activity is not evidence of completed work.
          (unless (hash-key? activities id) (hash-put! activities id #t)))
         ((and (eq? (hash-get activities id) #t) (equal? action "result")
               (eqv? kind 105) (vector? fields) (> (vector-length fields) 0)
               (exact-integer? (vector-ref fields 0)) (>= (vector-ref fields 0) 0))
          ;; Nix resProgress: done, expected, running, failed. Only done advances.
          (execution-progress! (list 'nix id 'done) (vector-ref fields 0)))
         ((and (eq? (hash-get activities id) #t) (equal? action "result")
               (eqv? kind 104) (vector? fields) (> (vector-length fields) 0)
               (string? (vector-ref fields 0)) (<= (string-length (vector-ref fields 0)) 128))
          (execution-progress! (list 'nix id 'phase (vector-ref fields 0)) 1))
         ((and (eq? (hash-get activities id) #t) (equal? action "stop"))
          (execution-progress! (list 'nix id 'completed) 1)
          ;; Keep the tombstone bounded: replayed starts/stops cannot renew.
          (hash-put! activities id 'completed)))))))
(def (make-test-progress-reader)
  (def nix (make-nix-progress-reader))
  (lambda (line)
    (nix line)
    (let (record (json-record line "@poo-progress "))
      (when (and (vector? record) (= (vector-length record) 2)
                 (string? (vector-ref record 0)) (<= (string-length (vector-ref record 0)) 128)
                 (exact-integer? (vector-ref record 1)) (>= (vector-ref record 1) 0))
        (execution-progress! (list 'worker (vector-ref record 0)) (vector-ref record 1))))))
