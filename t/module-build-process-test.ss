;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declarative Ops scripts; each child establishes its own source context.
(import :std/test :clan/poo/object
        (only-in :gerbil/expander core-read-module/sexp)
        "./qualification/module-bootstrap/objects.ss")
(export module-build-process-test)
(def (build-command script action)
  (displayln "BUILD-PROCESS " action) (force-output)
  (def result (.call script .run action))
  (displayln "BUILD-PROCESS-DONE " action " seconds=" (.get result seconds))
  (force-output)
  (def output (.get result output))
  (unless (zero? (.get result status))
    (display output)
    (error "normal build process failed" action (.get result status)))
  (when (ormap (lambda (marker) (string-contains output marker))
              '("*** ERROR" "ERROR CASE" "ERROR CHECK" "Heap overflow" "Stack overflow"))
    (display output)
    (error "normal build command reported an error" action))
  output)
(def (output-identities lib names)
  (map (lambda (name)
         (def path (path-expand (string-append name ".ssi") lib))
         (check-equal? (file-exists? path) #t)
         (let-values (((_prelude identity _namespace _body) (core-read-module/sexp path)))
           (check-equal? identity (string->symbol (string-append "core/" name)))
           (cons name identity))) names))
(def module-build-process-test
  (test-suite "Normal build script registers its own source package"
    (test-case "compile clean and new-process rebuild share one fixture and output identities"
      (def root (.get Fixture root))
      (def lib (path-expand "lib/core" (.get Fixture state)))
      (displayln "SOURCE-BUILD-FIXTURE " root) (force-output)
      (check-equal? (.slot? (.get Build environment) 'GERBIL_BUILD_CORES) #f)
      (displayln "BUILD-PROCESS-CORES " (getenv "GERBIL_BUILD_CORES" #f))
      (force-output)
      (when (.get Fixture cold) (check-equal? (file-exists? lib) #f))
      (check-equal?
        (call-with-input-file (path-expand "core-spec.ss" root) read-all)
        '((export core-spec)
          (def core-spec '("utilities/algorithms" "types" "core-spec"))))
      (def spec (call-with-input-string (build-command Build "spec") read))
      (def names (map cadr spec))
      ;; Module types now import the owned-read projection in addition to
      ;; JsonSchema receipt facts. Both libraries belong to the selected closure;
      ;; build-only tooling must not become an ordinary Module target.
      (check-equal? (length spec) 38)
      (check-equal? (length (filter (cut equal? <> "object-family/read-projection") names)) 1)
      (check-equal? (length (filter (cut equal? <> "type-facts/objects") names)) 1)
      (check-equal? (member "module-system/building/artifacts" names) #f)
      (build-command Build "compile")
      (def first-identities (output-identities lib names))
      ;; Core clean owns selected generated .scm files too. Keep a separate,
      ;; unselected sentinel so cleanup isolation is checked independently.
      (def unselected (path-expand "object-family/unselected-output.scm" lib))
      (call-with-output-file unselected (cut display "; unselected output\n" <>))
      (build-command Build "clean")
      (for-each (lambda (name)
                  (check-equal? (file-exists? (path-expand (string-append name ".ssi") lib)) #f)) names)
      (check-equal? (file-exists? (path-expand "object-family/syntax.scm" lib)) #f)
      (check-equal? (call-with-input-file unselected read-line) "; unselected output")
      ;; This must compile again, not merely print a new-process specification.
      ;; The same Script retains the exact source directory and GERBIL_PATH.
      (build-command Build "compile")
      (check-equal? (output-identities lib names) first-identities)
      (build-command Build "clean")
      (for-each (lambda (name)
                  (check-equal? (file-exists? (path-expand (string-append name ".ssi") lib)) #f)) names)
      (check-equal? (file-exists? (path-expand ".gerbil/module-build/build.ss" root)) #f)
      (check-equal? (file-exists? (path-expand "object-family/syntax.scm" lib)) #f)
      (check-equal? (call-with-input-file unselected read-line) "; unselected output")
      (displayln "BUILD-PROCESS-REBUILD-OK targets=" (length spec)))
    (test-case "same fixture rejects package mismatch and changed admission inputs"
      (def result (.call InputChecks .run))
      (def output (.get result output))
      (display output)
      (check-equal? (.get result status) 0)
      (check-equal? (and (string-contains output "MODULE-OK t/module-build-source-package-test.ss") #t) #t)
      (check-equal? (and (string-contains output "HARNESS-OK") #t) #t)
      (check-equal? (and (member "OK" (string-split output #\newline)) #t) #t)
      (check-equal? (ormap (cut string-contains output <>)
                     '("ERROR CASE" "ERROR CHECK" "ERROR HARNESS" "Heap overflow" "Stack overflow")) #f))))
