;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source data and probes only. No dispatcher or test runner.
(import :clan/poo/object
        (only-in :std/io/tempfile clear-temporary-file!)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil/expander core-resolve-library-module-path)
        "../module-bootstrap/fixtures.ss")
(export selection-fixture prepare-selection!)
(def (write-forms path forms)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (for-each (cut pretty-print <> port) forms))))
(def (observe-export datum marker forbidden?)
  ;; Preserve the real declaration, dependencies, contracts and export value.
  ;; Only execution of its deferred exports expression writes this probe.
  (cond
    ((not (pair? datum)) datum)
    ((eq? (car datum) 'exports:)
     (cons 'exports:
       (cons `(begin
                (call-with-output-file ,marker (lambda (port) (display "scope" port)))
                ,@(if forbidden? '((error "unselected real module scope evaluated")) '())
                ,(cadr datum))
             (cddr datum))))
    (else (cons (observe-export (car datum) marker forbidden?)
                (observe-export (cdr datum) marker forbidden?)))))
(def (selection-fixture repository)
  (.o .acquire: (lambda () (source-build-fixture repository #f))
      .release: (lambda (fixture)
                  (clear-temporary-file!
                    (path-normalize (path-expand "../.." (.get fixture root)))))))
(def (prepare-selection! fixture repository owner)
  (def root (.get fixture root))
  ;; Source-only dependency fallbacks are copied from the current qualified
  ;; package resolver, never from a mutable reference corpus or another Core.
  (def dependency (core-resolve-library-module-path ':clan/poo/object-state))
  (when (string-suffix? ".ss" dependency)
    (copy-fixture-tree (path-directory dependency)
      (path-expand "../clan/poo" root)
      (lambda (_path name kind)
        (and (not (string-prefix? "." name))
             (not (member name '("t" "tests" "doc" "docs")))
             (or (eq? kind 'directory) (string-suffix? ".ss" name)
                 (string-suffix? ".scm" name) (string=? name "gerbil.pkg"))))))
  (def declaration
    (if (eq? owner 'json-schema)
      '(yuanxu! mode: explicit source: "./modules" (json-schema))
      '(yuanxu! mode: explicit source: "./modules" (funflow))))
  (write-forms (path-expand "init.ss" root)
    (list '(import "./module-system/selection/init-syntax.ss") declaration))
  ;; Probe the existing execution library, not a replacement executor. In the
  ;; child process this marker must stay absent through init/build-spec demand.
  (def execution (path-expand "observability/testing-script.ss" root))
  (def execution-forms (call-with-input-file execution read-all))
  (write-forms execution
    (append execution-forms
      '((call-with-output-file "testing-execution.loaded"
          (lambda (port) (display "loaded" port))))))
  ;; The independent compiled-import gate owns this diagnostic directory.
  (create-directory* (path-expand "t/qualification/module-testing" root))
  (for-each
    (lambda (module)
      (def name (symbol->string module))
      (def interface (path-expand (string-append "modules/" name "/interface.ss") root))
      (def forms (call-with-input-file interface read-all))
      (write-forms interface
        (map (lambda (form) (observe-export form (string-append name ".scope")
                                           (not (eq? module owner)))) forms))
      ;; A stale hand-maintained atomic-test.ss path must fail this control.
      ;; Discovery and execution must follow the actual selected directory.
      (when (eq? module owner)
        (let (directory (path-expand (string-append "modules/" name "/tests") root))
          (for-each
            (lambda (file)
              (when (string-suffix? "-test.ss" file)
                (rename-file (path-expand file directory)
                             (path-expand (string-append "discovered-" file) directory))))
            (directory-files directory))))
      (unless (eq? module owner)
        (let* ((test (path-expand (string-append "modules/" name "/tests/atomic-test.ss") root))
               (original (call-with-input-file test read-all-as-string)))
          (call-with-output-file (list path: test truncate: #t)
            (lambda (port)
              (display original port)
              (newline port)
              (pretty-print
                `(begin
                   (call-with-output-file ,(string-append name ".test")
                     (lambda (out) (display "test" out)))
                   (error "unselected real module test evaluated")) port))))))
    '(json-schema funflow)))
