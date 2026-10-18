;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Opt-in qualification probes over the original expander, not an evaluator.
(import :gerbil/expander)
(export aws-startup-observation-start! aws-startup-observation-finish!)

(def restore '())
(def rows (make-hash-table))
(def frames '())
(def started #f)
(def interval 'startup)

(def (context-name)
  (let (context (current-expander-context))
    (if (expander-context? context) (expander-context-id context) 'top)))

(def (observe! kind parameter label)
  (def original (parameter))
  (set! restore (cons (cons parameter original) restore))
  (parameter
    (lambda arguments
      (def key (list kind (label arguments) (current-expander-phi)))
      (def frame (vector (real-time) 0.0))
      (dynamic-wind
        (lambda () (set! frames (cons frame frames)))
        (lambda () (apply original arguments))
        (lambda ()
          (let* ((elapsed (- (real-time) (vector-ref frame 0)))
                 (entry (hash-ref rows key (vector 0 0.0 0.0))))
            (set! frames (cdr frames))
            (when (pair? frames)
              (vector-set! (car frames) 1 (+ elapsed (vector-ref (car frames) 1))))
            (vector-set! entry 0 (+ 1 (vector-ref entry 0)))
            (vector-set! entry 1 (+ elapsed (vector-ref entry 1)))
            (vector-set! entry 2 (+ (- elapsed (vector-ref frame 1)) (vector-ref entry 2)))
            (hash-put! rows key entry)))))))

(def (aws-startup-observation-start! (label 'startup))
  (when (or (getenv "CORE_AWS_TRACE" #f) (getenv "CORE_AWS_STARTUP_TRACE" #f)
            (and (eq? label 'build-graph) (getenv "CORE_AWS_GRAPH_TRACE" #f)))
    (when started (error "AWS expansion probe is already active" interval))
    (set! interval label)
    (hash-clear! rows)
    (set! frames '())
    (set! started (real-time))
    (observe! 'import current-expander-module-import
      (lambda (arguments) (syntax->datum (car arguments))))
    (observe! 'module-eval current-expander-module-eval
      (lambda (arguments)
        (let (value (car arguments))
          (if (expander-context? value) (expander-context-id value) (syntax->datum value)))))
    (observe! 'compile current-expander-compile (lambda (_arguments) (context-name)))
    (observe! 'eval current-expander-eval (lambda (_arguments) (context-name)))))

(def (aws-startup-observation-finish!)
  (when started
    ;; Restore before printing. Inclusive time overlaps; self time subtracts
    ;; nested observed callbacks and must not be summed with inclusive time.
    (for-each (lambda (entry) ((car entry) (cdr entry))) restore)
    (set! restore '())
    (parameterize ((current-output-port (current-error-port)))
      (displayln "AWS-STARTUP observed-seconds=" (- (real-time) started)
                 " interval=" interval)
      (let loop ((entries (list-sort
                           (lambda (a b) (> (vector-ref (cdr a) 2)
                                            (vector-ref (cdr b) 2)))
                           (hash->list rows)))
                 (remaining 25))
        (unless (or (null? entries) (zero? remaining))
          (displayln "AWS-STARTUP-OWNER " (car entries))
          (loop (cdr entries) (- remaining 1))))
      (force-output))
    (set! started #f)))
