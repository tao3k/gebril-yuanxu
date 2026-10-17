;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil/runtime/error ContractViolation?)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/source this-source-file)
        (only-in :std/make make)
        (only-in :clan/poo/object .get .ref .call .cc .o .+)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/modules/building/build-projection poo-flow-core-write-build-entry)
        (only-in :core/module-system/source/admission module-source-type module-source-read)
        (only-in :core/observability/testing-case poo-flow-test-case))
(export module-json-schema-publication-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def (write-file path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (lambda (p) (display text p))))
(def (remove-tree path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-tree (path-expand name path))) (directory-files path))
           (delete-directory path)) (delete-file path)))
(def (with-copy test)
  (let (copy (make-temporary-file-name "json-schema-publication-"))
    (dynamic-wind
     (lambda ()
       (write-file (path-expand "gerbil.pkg" copy)
         "(package: core)")
       (write-file (path-expand "init.ss" copy) "(poo-flow! source: \"modules\" (json-schema))")
       (for-each (lambda (file)
                   (when (string=? (path-extension file) ".ss")
                     (write-file (path-expand (string-append "modules/json-schema/" file) copy)
                       (module-source-read (path-expand (string-append "modules/json-schema/" file) root)))))
                 (directory-files (path-expand "modules/json-schema" root))))
     (lambda () (test copy)) (lambda () (remove-tree copy)))))
(def module-json-schema-publication-test
  (test-suite "Real JsonSchema publication and native private-source closure"
    (poo-flow-test-case "real Core init publishes contracts and derives all imported sources once"
      (let* ((view (poo-flow-load-modules (path-expand "init.ss" root)))
             (graph (.get view build-graph))
             (scope (.get view modules json-schema))
             (contract (.call scope contract 'test/port
                        '((type . "object") (required . ("port"))
                          (properties . ((port . ((type . "integer") (minimum . 1)))))))))
        (check-equal? (.get view selected-graph module-order) '(json-schema))
        (check-equal? (> (length (.get graph entries)) 15) #t)
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit contract (.o port: 80) #f)) #t)
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit contract (.o port: "bad") #f)) #f)
        (check-exception (.call scope compile 4) ContractViolation?)
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit (.get scope types scope)
                         (.+ scope (.o defaults: (.o scheam: '()))) #f)) #f)
        (check-equal? (poo-flow-validation-evidence-accepted?
                       (poo-flow-contract-admit (.get scope types scope)
                         (.+ scope (.o compile: 7)) #f)) #f)
        (check-equal? (.get scope defaults schema) '((type . "object")))))
    (poo-flow-test-case "private helper changes invalidate cached Graph; a fresh source session succeeds"
      (with-copy
       (lambda (copy)
         (let* ((view (poo-flow-load-modules (path-expand "init.ss" copy)))
                (graph (.get view build-graph))
                (file (path-expand "modules/json-schema/functional.ss" copy)))
           (check-equal? (> (length (.get graph entries)) 15) #t)
           (write-file file (string-append (module-source-read file) "\n;; changed source generation\n"))
           (check-exception ((.get graph admit-current)) error?)
           (check-equal? (.get (poo-flow-load-modules (path-expand "init.ss" copy)) selected-graph module-order)
                         '(json-schema))))))
    (poo-flow-test-case "private source cycle and publication self-import are rejected"
      (with-copy
       (lambda (copy)
         (let* ((base (path-expand "modules/json-schema" copy))
                (types (path-expand "types.ss" base))
                (original (module-source-read types)))
           (write-file types (string-append "(import \"cycle-a.ss\")\n" original))
           (write-file (path-expand "cycle-a.ss" base) "(import \"cycle-b.ss\") (export #t)")
           (write-file (path-expand "cycle-b.ss" base) "(import \"cycle-a.ss\") (export #t)")
           (check-exception (.get (poo-flow-load-modules (path-expand "init.ss" copy)) build-graph) (lambda (_e) #t))
           (write-file (path-expand "cycle-b.ss" base) "(import \"interface.ss\") (export #t)")
           (check-exception (.get (poo-flow-load-modules (path-expand "init.ss" copy)) build-graph) (lambda (_e) #t))))))
    (poo-flow-test-case "generated real JsonSchema roots compile as a bounded native library"
      (with-copy
       (lambda (copy)
         (let* ((artifact (poo-flow-core-write-build-entry
                           (path-expand "init.ss" copy) (path-expand "generated" copy)))
                (spec (.get artifact spec)))
           (check-equal? (> (length spec) 15) #t)
           (make spec srcdir: (.get artifact source-root)
                 libdir: (path-expand "lib" copy) bindir: (path-expand "bin" copy))
           (check-equal? (module-source-type
                           (path-expand
                             (string-append (cadar (reverse spec)) ".ssi") (path-expand "lib" copy))) 'regular)))))
))
