;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :clan/poo/object .get)
        (only-in :gerbil/expander core-import-module module-context-path)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in "qualification/module-publication/fixtures.ss" with-publication-source)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read current-module-source-observer
                 call-with-module-source-operation-measurement))
(export module-reader-tool-context-test)
(def root (getenv "CORE_QUALIFICATION_ROOT" #f))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (exception)
      (let (text (if (Error? exception)
                    (call-with-output-string
                      (lambda (port)
                        (display (Error-message exception) port)
                        (write (Error-irritants exception) port))) ""))
        (if (pregexp-match pattern text) #t
            (begin
              (displayln "UNEXPECTED-REJECTION " (substring text 0 (min 400 (string-length text))))
              #f))))
      (lambda () (thunk) #f)))
  (def (with-change relative transform test)
    (let* ((path (path-expand relative root)) (text (module-source-read path)))
      (dynamic-wind
        (lambda () (write-source path (transform text)))
        test
        (lambda () (write-source path text)))))
  (def module-reader-tool-context-test
    (if root
    (test-suite "Compiler tool reuse preserves source confinement"
      (test-case "installed execution does not own an unrelated checkout"
        (def tool (core-import-module ':yuanxu/module-system/source/declaration))
        (check-equal? (path-extension (module-context-path tool)) ".ssi")
        (with-publication-source
          (lambda (_root _module-root _source view)
            (def graph (.get view build-graph))
            (with-change "module-system/source/declaration.ss"
              (lambda (text) (string-append text "\n;; unrelated installed-tool checkout edit\n"))
              (lambda ()
                ((.get graph admit-current))
                (check-equal? (.get graph selected-graph module-order) '(custom/example)))))))
      (test-case "captured installed artifact path remains part of runtime identity"
        (def tool (core-import-module ':yuanxu/module-system/source/declaration))
        (def path (module-context-path tool))
        (def reader (module-publication-reader))
        (dynamic-wind
          (lambda () (slot-set! tool 'path (string-append path ".changed")))
          (lambda ()
            (check-equal? (rejects? "compiler tool context changed"
                            (lambda () ((.get reader admit-current)))) #t))
          (lambda () (slot-set! tool 'path path))))
      (test-case "observer return cannot change installed tool identity"
        (def tool (core-import-module ':yuanxu/module-system/source/declaration))
        (def path (module-context-path tool))
        (def reader (module-publication-reader))
        (dynamic-wind
          void
          (lambda ()
            (parameterize ((current-module-source-observer
                (lambda (event _amount)
                  (when (and (pair? event) (eq? (car event) 'publication-guard-end))
                    (slot-set! tool 'path (string-append path ".changed"))
                    (current-module-source-observer #f)))))
              (check-equal? (rejects? "compiler tool context changed"
                              (lambda () ((.get reader admit-current)))) #t)))
          (lambda () (slot-set! tool 'path path))))
      (test-case "exact tool bytes remain guarded after Graph construction"
        (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
               (graph (.get view build-graph)))
          (check-equal? (and (member 'json-schema (.get graph selected-graph module-order)) #t) #t)
          (with-change "module-system/source/declaration.ss"
            (lambda (text) (string-append text "\n;; changed tool source\n"))
            (lambda ()
              (check-equal? (rejects? "tool source changed|stale|refused"
                              (lambda () ((.get graph admit-current)))) #t)))))
      (test-case "bound owner paths skip rediscovery while source bytes remain fresh"
        (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph)
        (defvalues (graph counts)
          (call-with-module-source-operation-measurement
            (lambda () (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
            accounting?: #f))
        (check-equal? (or (hash-get counts '(calls reader-owned-source-resolution)) 0) 0)
        (check-equal? (> (or (hash-get counts '(calls reader-bound-source-reuse)) 0) 0) #t)
        (def reads 0)
        (for-each (lambda (row)
                    (when (and (pair? (car row)) (eq? (caar row) 'physical-reads))
                      (set! reads (+ reads (cdr row))))) (hash->list counts))
        (check-equal? (> reads 0) #t)
        ((.get graph admit-current)))
      (test-case "removed owned tool remains a required input in a fresh Graph"
        (def graph (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph))
        (def file (path-expand "module-system/source/declaration.ss" root))
        (def backup (string-append file ".saved"))
        (dynamic-wind
          (lambda () (rename-file file backup))
          (lambda ()
            (check-exception ((.get graph admit-current)) (lambda (_failure) #t))
            (check-exception (.get (yuanxu-load-modules (path-expand "init.ss" root)) build-graph)
                             (lambda (_failure) #t)))
          (lambda () (rename-file backup file))))
      (test-case "foreign same-identity declaration is rejected before evaluation"
        (call-with-temporary-directory "foreign-tool-context"
          (lambda (foreign)
            (let ((path (path-expand "declaration.ss" foreign))
                  (marker (path-expand "evaluated" foreign)))
              (write-source path
                (string-append "package: yuanxu/module-system/source\n"
                  "(call-with-output-file "
                  (call-with-output-string (lambda (port) (write marker port)))
                  " (lambda (p) (display \"unexpected\" p)))\n"))
              (with-change "modules/json-schema/types.ss"
                (lambda (text)
                  (string-append "(import "
                    (call-with-output-string (lambda (port) (write path port))) ")\n" text))
                (lambda ()
                  (check-equal? (rejects? "source import leaves its Module and package kernel"
                                  (lambda () (.get (yuanxu-load-modules
                                                     (path-expand "init.ss" root)) build-graph))) #t)
                  (check-equal? (file-exists? marker) #f)))))))
      (test-case "private cycles and interface self-import reject in the complete source package"
        ;; Establish the positive source closure before introducing either cycle.
        (check-equal? (> (length (.get (yuanxu-load-modules
                                        (path-expand "init.ss" root)) build-graph entries)) 15) #t)
        (let* ((base (path-expand "modules/json-schema" root))
               (first (path-expand "cycle-a.ss" base))
               (second (path-expand "cycle-b.ss" base)))
          (dynamic-wind
            (lambda ()
              (write-source first "(import \"cycle-b.ss\") (export #t)")
              (write-source second "(import \"cycle-a.ss\") (export #t)"))
            (lambda ()
              (with-change "modules/json-schema/types.ss"
                (lambda (text) (string-append "(import \"cycle-a.ss\")\n" text))
                (lambda ()
                  (check-exception (.get (yuanxu-load-modules
                                          (path-expand "init.ss" root)) build-graph)
                                   (lambda (_e) #t))
                  (write-source second "(import \"interface.ss\") (export #t)")
                  (check-exception (.get (yuanxu-load-modules
                                          (path-expand "init.ss" root)) build-graph)
                                   (lambda (_e) #t)))))
            (lambda () (delete-file first) (delete-file second)))))
      (test-case "Module reverse role dependency remains rejected before expansion"
        (with-change "modules/json-schema/types.ss"
          (lambda (text) (string-append "(import \"interface.ss\")\n" text))
          (lambda ()
            (check-equal? (rejects? "YUANXU-MODULE-E007 reversed module role dependency"
                            (lambda () (.get (yuanxu-load-modules
                                               (path-expand "init.ss" root)) build-graph))) #t)))))
    (begin
      (displayln "SKIP module-reader-tool-context: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "module-reader-tool-context (source-only opt-in)" (void)))))
