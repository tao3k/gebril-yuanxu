;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/error Error? Error-message Error-irritants)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/admission module-source-read))
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
      (test-case "exact tool bytes remain guarded after Graph construction"
        (let* ((view (yuanxu-load-modules (path-expand "init.ss" root)))
               (graph (.get view build-graph)))
          (check-equal? (.get graph selected-graph module-order) '(json-schema))
          (with-change "module-system/source/declaration.ss"
            (lambda (text) (string-append text "\n;; changed tool source\n"))
            (lambda ()
              (check-equal? (rejects? "tool source changed|stale|refused"
                              (lambda () ((.get graph admit-current)))) #t)))))
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
