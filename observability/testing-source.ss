;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Observe public Gerbil expander completion callbacks, never dispatch tests.
(import (only-in :gerbil/expander current-expander-module-import
                 current-expander-module-eval current-expander-eval
                 current-expander-context current-expander-phi module-context? expander-context-id module-context-path
                 core-resolve-identifier core-context-root feature-binding?)
        (only-in :yuanxu/ops/progress call-with-execution-progress
                 current-execution-progress execution-progress!)
        (only-in :yuanxu/observability/output yuanxu-write-observation-line!))
(export install-test-source-observation! stop-test-source-observation!
        test-source-observation-active?)

;; One Gerbil invocation owns these callbacks and bounded weak observations.
;; No timer, thread, Module context root, compiler or Harness is created here.
(def restore #f)
(def (test-source-observation-active?) (procedure? restore))
(def (stop-test-source-observation!)
  (when (procedure? restore) (restore) (set! restore #f)))

(def (install-test-source-observation!)
  (when (and (not restore)
             (feature-binding?
               (core-resolve-identifier 'yuanxu-module-test-observation 0 (core-context-root))))
   (let ()
    (def native-import (current-expander-module-import))
    (def native-module-eval (current-expander-module-eval))
    (def native-eval (current-expander-eval))
    (def imported (make-hash-table-eq weak-keys: #t))
    (def evaluated (make-hash-table-eq weak-keys: #t))
    (def bodies (make-hash-table-eq weak-keys: #t))
    (def lock (make-mutex 'test-source-observation))
    (def count 0)
    (def spans 0)
    (def active? #t)
    (def publish
      (call-with-execution-progress #f #f
        (lambda (state)
          (lambda ()
            (parameterize ((current-execution-progress (list state)))
              (execution-progress! 'gerbil-module-completions count))))))
    (def (completed seen context (phase #t))
      (when (module-context? context)
        (mutex-lock! lock)
        (try
          (when (and active? (< count 16384)
                     (not (memv phase (hash-ref seen context '()))))
            (hash-put! seen context (cons phase (hash-ref seen context '())))
            (set! count (+ count 1))
            (publish))
          (finally (mutex-unlock! lock)))))
    (def (completed-span phase context started)
      (def seconds (/ (- (current-jiffy) started) (jiffies-per-second)))
      (when (and (module-context? context) (>= seconds .5))
        (mutex-lock! lock)
        (try
          (when (and active? (< spans 64))
            (set! spans (+ spans 1))
            (let (path (module-context-path context))
              (yuanxu-write-observation-line!
                "test-source phase=%s inclusive-seconds=%s module=%s input-kind=%s"
                phase seconds (expander-context-id context)
                (if (string? path) (path-extension path) 'submodule))))
          (finally (mutex-unlock! lock)))))
    (def observe-import
      (lambda (path reload?)
        (def started (current-jiffy))
        (let (context (native-import path reload?))
          (completed imported context)
          (completed-span 'import context started)
          context)))
    (def observe-module-eval
      (lambda (context)
        (def started (current-jiffy))
        (begin0 (native-module-eval context)
          (completed evaluated context)
          (completed-span 'evaluation context started))))
    (def observe-eval
      (lambda (expression)
        (def context (current-expander-context))
        (def phase (current-expander-phi))
        (def started (current-jiffy))
        (with-catch
          (lambda (failure)
            ;; Attribute a real failed Gerbil evaluation without dumping source
            ;; text, swallowing the error, or counting failure as progress.
            (when active?
              (yuanxu-write-observation-line! "test-source evaluation-failed module=%s phi=%s"
                (and (module-context? context) (expander-context-id context)) phase))
            (raise failure))
          (lambda ()
            (begin0 (native-eval expression)
              (completed bodies context phase)
              (completed-span 'body context started))))))
    (set! restore
      (lambda ()
        ;; Do not overwrite another Gerbil consumer's later parameter binding.
        (mutex-lock! lock)
        (try
          (set! active? #f)
          (hash-clear! imported) (hash-clear! evaluated) (hash-clear! bodies)
          (finally (mutex-unlock! lock)))
        (when (eq? (current-expander-module-import) observe-import)
          (current-expander-module-import native-import))
        (when (eq? (current-expander-module-eval) observe-module-eval)
          (current-expander-module-eval native-module-eval))
        (when (eq? (current-expander-eval) observe-eval)
          (current-expander-eval native-eval))))
    (current-expander-module-import observe-import)
    (current-expander-module-eval observe-module-eval)
    (current-expander-eval observe-eval))))
