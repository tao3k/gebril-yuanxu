;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Imported in a fresh native process after the consumer sources are removed.
(import :std/test :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil/expander core-import-module module-context-path)
        (only-in :gerbil/runtime list-modules)
        (rename-in :yuanxu/compiled-bindings/only
                   (namespace only-namespace) (atomic only-atomic))
        (rename-in :yuanxu/compiled-bindings/renamed
                   (namespace renamed-namespace)))
(export compiled-binding-test)
(def root (path-expand "../../.." (path-directory (this-source-file))))
(def (write-text path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def compiled-binding-test
  (test-suite "Native compiled namespace binding"
    (test-case "compiler artifacts are actually imported"
      (for-each
        (lambda (name)
          (def path (module-context-path (core-import-module name)))
          (check-equal? (string-suffix? ".ssi" path) #t))
        '(:yuanxu/compiled-bindings/only :yuanxu/compiled-bindings/renamed))
      (check-equal? (file-exists? (path-expand "compiled-bindings/only.ss" root)) #f)
      (check-equal? (file-exists? (path-expand "compiled-bindings/renamed.ss" root)) #f)
      (for-each
        (lambda (name)
          (def entry (assoc name (list-modules)))
          (check-equal? (and entry (string? (cdr entry))
                           (string-suffix? ".o1" (cdr entry))) #t))
        '("yuanxu/init~0" "yuanxu/compiled-bindings/only~0" "yuanxu/compiled-bindings/renamed~0"))
      (check-equal? (file-exists? (path-expand "testing-execution.loaded" root)) #f))
    (test-case "only-in and rename-in return one namespace without forcing values"
      (def modules (only-namespace))
      (check-equal? (eq? modules (only-namespace)) #t)
      (check-equal? (eq? modules (renamed-namespace)) #t)
      (check-equal? (.all-slots/sort modules) '(json-schema))
      (check-equal? (.slot? modules 'json-schema) #t)
      (check-equal? (.slot? modules 'missing) #f)
      (check-equal? (.ref/cached modules 'json-schema) #f)
      (def module (.get modules json-schema))
      (check-equal? (.all-slots/sort module) '(identity scope tests))
      (check-equal? (.ref/cached module 'scope) #f)
      (check-equal? (.ref/cached module 'tests) #f)
      (check-equal? (file-exists? (path-expand "json-schema.scope" root)) #f)
      (check-equal? (file-exists? (path-expand "testing-execution.loaded" root)) #f))
    (test-case "compiled binding keeps test identity and source guards"
      (def tests (only-atomic))
      (check-equal? (eq? tests (.get (renamed-namespace) json-schema tests)) #t)
      (.call tests .run)
      (check-equal? (file-exists? (path-expand "json-schema.scope" root)) #f)
      (def file (car (.get tests spec)))
      (def original (call-with-input-file file read-all-as-string))
      (dynamic-wind
        (lambda () (write-text file (string-append original "\n;; changed compiled test input\n")))
        (lambda () (check-exception (.call tests .run) error?))
        (lambda () (write-text file original))))
    (test-case "compiled reads recheck init while a captured value stays a snapshot"
      (def captured (only-namespace))
      (def file (path-expand "init.ss" root))
      (def original (call-with-input-file file read-all-as-string))
      (dynamic-wind
        (lambda () (write-text file (string-append original "\n;; changed compiled init input\n")))
        (lambda ()
          (check-exception (only-namespace) error?)
          (check-exception (renamed-namespace) error?)
          (check-equal? (.slot? captured 'json-schema) #t))
        (lambda () (write-text file original))))))
