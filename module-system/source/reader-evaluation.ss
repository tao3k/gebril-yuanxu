;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Observe Gerbil evaluation and release completed interpreter bodies.
(import (only-in :gerbil/expander current-expander-compile current-expander-eval
                 current-expander-context current-expander-phi module-context?
                 module-context-code module-context-path expander-context-table
                 module-context-import)
        (only-in :gerbil/runtime __compile-top __compile-top-source)
        (only-in :gerbil/expander module-import? module-import-source module-export-context
                 module-import-phi import-set? import-set-source import-set-phi)
        (only-in :std/list/list append-map)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads %record-slot-reads!)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 module-source-measure-operation module-source-type)
        (only-in :gerbil/runtime/loader list-modules))
(export register-reader-wrapper! reader-evaluation-observers observe-reader-work release-reader-expansions!
        remove-reader-tree reader-body)

(def (register-reader-wrapper! owned path origin)
  ;; Record the native spelling and its canonical alias while the wrapper's
  ;; directory is live. A later reader can see a foreign, completed context
  ;; whose temporary directory has already been removed.
  (def canonical (path-normalize path))
  (hash-put! owned canonical origin)
  (unless (equal? path canonical) (hash-put! owned path origin)))

(def (reader-evaluation-observers owned completed
                                  (initialize (lambda (_context action) (action)))
                                  (runtime-context? (lambda (_context) #f)))
  ;; Gerbil runtime imports bypass current-expander-module-eval. Pair the exact
  ;; phi-zero module body with its compiled program, then observe successful
  ;; evaluation of that same program. Macro-phase or partial evaluation alone
  ;; grants no release capability. Delegate all Gerbil results without alteration.
  (def gerbil-compile (current-expander-compile))
  (def gerbil-eval (current-expander-eval))
  (def pending (make-hash-table-eq))
  (def (code expression)
    (if (##source? expression) (##source-code expression) expression))
  (def (runtime-import? entry)
    (cond
     ((module-context? entry) (runtime-context? entry))
     ((module-import? entry)
      (and (zero? (module-import-phi entry))
           (runtime-context? (module-export-context (module-import-source entry)))))
     ((import-set? entry)
      (and (zero? (import-set-phi entry)) (runtime-context? (import-set-source entry))))
     (else #f)))
  (def (import-parts program)
    (and (or (eq? gerbil-compile __compile-top) (eq? gerbil-compile __compile-top-source))
         (eq? gerbil-eval ##eval)
      (let* ((wrapped? (and (pair? program) (eq? (car program) __noexpand:)))
             (body (code (if wrapped? (cdr program) program))))
        (def (wrap expression) (if wrapped? (cons __noexpand: expression) expression))
        (and (pair? body) (eq? (code (car body)) 'begin)
          (let (split? #f)
            (def parts
              (append-map
                (lambda (expression)
                  (def form (code expression))
                  (if (and (list? form) (= (length form) 2)
                           (eq? (code (car form)) '__eval-import)
                           (pair? (code (cadr form)))
                           (eq? (code (car (code (cadr form)))) 'quote))
                    (let (entries (cadr (code (cadr form))))
                      (if (and (list? entries) (ormap runtime-import? entries))
                        (begin
                          (set! split? #t)
                          (map (lambda (entry)
                                 (cons (and (runtime-import? entry) entry)
                                   (wrap (##make-source
                                     (list (car form) (list 'quote (list entry)))
                                     (and (##source? expression) (##source-locat expression))))))
                            entries))
                        (list (cons #f (wrap expression)))))
                    (list (cons #f (wrap expression)))))
                (cdr body)))
            (and split? parts))))))
  (def (initialize-runtime entry expression)
    (unless (runtime-import? entry) (error "runtime import provenance changed"))
    (def failed? #f)
    (def failure #f)
    (defvalues (results reads)
      (%call-with-recorded-slot-reads
        (lambda ()
          (with-catch (lambda (cause) (set! failed? #t) (set! failure cause) '())
            (lambda () (call-with-values (lambda () (gerbil-eval expression)) list))))))
    (when failed? (%record-slot-reads! reads) (raise failure))
    (unless (runtime-import? entry) (error "runtime import provenance changed during initialization"))
    (apply values results))
  (def (evaluate-program program parts)
    ;; Never split an open compiler/evaluator or observer execution. The
    ;; standard compiler's exact import descriptors retain Gerbil's ordering,
    ;; one-time promises and errors; no loader or result cache is introduced.
    (if (or (not parts) (current-module-source-observer)
            (not (owned-read-function-scope?)))
      (gerbil-eval program)
      (let loop ((parts parts))
        (def part (car parts))
        (def (invoke)
          (if (car part) (initialize-runtime (car part) (cdr part)) (gerbil-eval (cdr part))))
        (if (null? (cdr parts)) (invoke)
          (begin (invoke) (loop (cdr parts)))))))
  (def (evaluate-body program label parts)
    (def verbosity (string->number (getenv "GERBIL_BUILD_VERBOSE" "0")))
    (if (not (and verbosity (>= verbosity 4))) (evaluate-program program parts)
      (let (before (list->hash-table (map (lambda (row) (cons (car row) #t)) (list-modules))))
        (begin0 (evaluate-program program parts)
          (write (list 'READER-NATIVE-LOAD label
                   (filter (lambda (row) (not (hash-key? before (car row)))) (list-modules))))
          (newline) (force-output)))))
  (def (body-event stage context)
    (let (observer (current-module-source-observer))
      (when observer
        (observer stage 1)
        (when (eq? stage 'reader-body-expanded)
          ;; Scalar widths distinguish binding/edge growth from the number of
          ;; source bodies. Do not retain runtime contexts in telemetry keys.
          (observer 'reader-private-bindings (hash-length (expander-context-table context)))
          (observer 'reader-private-import-edges (length (module-context-import context))))
        ;; Only interface bodies receive phase snapshots. Other private bodies
        ;; contribute scalar work counts without sampling once per dependency.
        (when (string-suffix? "-interface.ss" (module-context-path context))
          (observer
            (list 'reader-declaration
              (cons 'bindings (hash-length (expander-context-table context)))
              (cons 'imports (length (module-context-import context)))) 1)))))
  (def (owned-body-origin context form)
    (and (module-context? context) (zero? (current-expander-phi))
         (eq? form (module-context-code context))
         (string? (module-context-path context))
         (hash-get owned (module-context-path context))))
  (def (compile form)
    (let* ((context (current-expander-context))
           (origin (owned-body-origin context form)))
      (when origin (body-event 'reader-body-expanded context))
      (let (program
              (if (not origin) (gerbil-compile form)
                (observe-reader-work 'reader-compile-start 'reader-compile-end
                  (lambda () (gerbil-compile form)))))
        (when (and (pair? program) origin)
          (body-event 'reader-body-compiled context)
          (hash-put! pending program (list context form origin (import-parts program))))
        program)))
  (def (evaluate program)
    (let (entry (hash-get pending program))
      (call-with-values
        (lambda ()
          (if (not entry) (gerbil-eval program)
            (observe-reader-work 'reader-eval-start 'reader-eval-end
              (lambda ()
                (def context (car entry))
                (def origin (caddr entry))
                (def label (if (string? origin) origin (module-context-path context)))
                (module-source-measure-operation (list 'reader-initialization label)
                  (lambda ()
                    (initialize context
                      (lambda ()
                        (module-source-measure-operation (list 'reader-initializer-body label)
                          (lambda () (evaluate-body program label (cadddr entry))))))))))))
        (lambda results
          (when entry
            (hash-remove! pending program)
            (hash-put! completed (car entry) (cadr entry))
            (body-event 'reader-body-evaluated (car entry)))
          (apply values results)))))
  (values compile evaluate))

;; Closed event labels extend the existing test observer, not an execution
;; wrapper or a profiler-owned object graph. Preserve all values and failures.
(def (observe-reader-work start end action)
  (module-source-measure-operation start
    (lambda ()
      (let (observer (current-module-source-observer))
        (if (not observer) (action)
          (dynamic-wind
            (lambda () (observer (list start 'body) 1))
            action
            (lambda () (observer (list end 'body) 1))))))))
(def (release-reader-expansions! completed)
  ;; Only Core-generated interpreter wrappers occur in this completed set.
  ;; They are never compiler inputs: building projects the guarded originals.
  ;; Keep the context, imports, bindings, phases and runtime promise intact.
  ;; In particular, do not import an unused wrapper merely to find a context.
  (def released 0)
  (def interface-bindings 0)
  (hash-for-each
    (lambda (context code)
      (when (and code (eq? code (module-context-code context)))
        (let (path (module-context-path context))
          (when (and (string? path) (string-suffix? "-interface.ss" path))
            (set! interface-bindings
              (+ interface-bindings (hash-length (expander-context-table context))))))
        (slot-set! context 'code #f)
        (set! released (+ released 1)))) completed)
  (when (current-module-source-observer)
    ((current-module-source-observer)
      (list 'reader-lifetime (cons 'completed (hash-length completed))
                             (cons 'released released)
                             (cons 'evaluated-interface-bindings interface-bindings)) 1))
  (hash-clear! completed)
  interface-bindings)
(def (remove-reader-tree path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-reader-tree (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (reader-body forms (imports '()))
  ;; Preparation owns these runtime compiler headers; preserve its prelude while
  ;; assigning a fresh private identity to this interpreter-only projection.
  (let loop ((tail forms) (prelude '()))
    (cond
     ((and (pair? tail) (eq? (car tail) 'prelude:))
      (loop (cddr tail) (list (car tail) (cadr tail))))
     ((and (pair? tail) (memq (car tail) '(package: namespace:)))
      (loop (cddr tail) prelude))
     (else (append prelude imports tail)))))
