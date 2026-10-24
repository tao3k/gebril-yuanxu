;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declarative Ops scripts; each child establishes its own source context.
(import :std/test :clan/poo/object
        (only-in :yuanxu/ops/func run-script)
        (only-in :gerbil/expander core-read-module/sexp)
        "./qualification/module-bootstrap/objects.ss")
(export module-build-process-test)
(def (build-command script action)
  (displayln "BUILD-PROCESS " action) (force-output)
  ;; Forward actual compiler output while retaining the captured result for
  ;; assertions. The outer Harness must observe child progress as it occurs.
  (def execution
    (if (equal? action "compile")
      (.cc script 'environment
        (.+ (.get script environment) (.o GERBIL_BUILD_VERBOSE: "1")))
      script))
  (def result (run-script execution (list action) output-port: (current-error-port)))
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
(def (compiled-path root lib name)
  (let-values (((_prelude identity _namespace _body)
                (core-read-module/sexp (path-expand (string-append name ".ss") root))))
    (values (path-expand (string-append (symbol->string identity) ".ssi") lib) identity)))
(def (output-identities root lib names)
  (map (lambda (name)
         (let-values (((path expected) (compiled-path root lib name)))
           (check-equal? (file-exists? path) #t)
           (let-values (((_prelude identity _namespace _body) (core-read-module/sexp path)))
             (check-equal? identity expected)
             (cons name identity)))) names))
(def module-build-process-test
  (test-suite "Normal build script registers its own source package"
    (test-case "compile clean and new-process rebuild share one fixture and output identities"
      (def root (.get Fixture root))
      (def lib (path-expand "lib" (.get Fixture state)))
      (displayln "SOURCE-BUILD-FIXTURE " root) (force-output)
      (check-equal? (.slot? (.get Build environment) 'GERBIL_BUILD_CORES) #f)
      (displayln "BUILD-PROCESS-CORES " (getenv "GERBIL_BUILD_CORES" #f))
      (force-output)
      (when (.get Fixture cold) (check-equal? (file-exists? (path-expand "yuanxu" lib)) #f))
      (check-equal?
        (call-with-input-file (path-expand "core-spec.ss" root) read-all)
        '((export core-spec core-public-roots)
          (def core-public-roots '())
          (def core-spec '("prelude" "utilities/algorithms" "object-types/contracts" "object-types/ports" "core-spec"))))
      (def spec (call-with-input-string (build-command Build "spec") read))
      (def names (map cadr spec))
      ;; Module types now import the owned-read projection in addition to
      ;; JsonSchema receipt facts. Both libraries belong to the selected closure;
      ;; build-only tooling must not become an ordinary Module target.
      (check-equal? (length (filter (cut equal? <> "prelude") names)) 1)
      (check-equal? (length (filter (cut equal? <> "object-family/read-projection") names)) 1)
      (check-equal? (length (filter (cut equal? <> "object-types/facts") names)) 1)
      (check-equal? (member "module-system/building/artifacts" names) #f)
      (build-command Build "compile")
      (def first-identities (output-identities root lib names))
      ;; The language's declared identity is not the root package prefix.
      ;; A fresh process must reuse its real products, without alias outputs.
      (def prelude-products
        (list (path-expand "tao3k/yuanxu/prelude.ssi" lib)
              (path-expand "static/tao3k__yuanxu__prelude.scm" lib)))
      (def (product-times)
        (map (lambda (path)
               (time->seconds (file-info-last-modification-time (file-info path))))
             prelude-products))
      (def first-times (product-times))
      (def hot-output (build-command Build "compile"))
      (check-equal? (string-contains hot-output "... compile ") #f)
      (check-equal? (string-contains hot-output "... execute compile job ") #f)
      (check-equal? (product-times) first-times)
      (check-equal? (file-exists? (path-expand "yuanxu/prelude.ssi" lib)) #f)
      (check-equal? (file-exists? (path-expand "static/yuanxu__prelude.scm" lib)) #f)
      ;; Core clean owns selected generated .scm files too. Keep a separate,
      ;; unselected sentinel so cleanup isolation is checked independently.
      (def unselected (path-expand "yuanxu/object-family/unselected-output.scm" lib))
      (call-with-output-file unselected (cut display "; unselected output\n" <>))
      (build-command Build "clean")
      (for-each (lambda (name)
                  (let-values (((path _identity) (compiled-path root lib name)))
                    (check-equal? (file-exists? path) #f))) names)
      (check-equal? (file-exists? (path-expand "yuanxu/object-family/syntax.scm" lib)) #f)
      (check-equal? (call-with-input-file unselected read-line) "; unselected output")
      ;; This must compile again, not merely print a new-process specification.
      ;; The same Script retains the exact source directory and GERBIL_PATH.
      (build-command Build "compile")
      (check-equal? (output-identities root lib names) first-identities)
      (build-command Build "clean")
      (for-each (lambda (name)
                  (let-values (((path _identity) (compiled-path root lib name)))
                    (check-equal? (file-exists? path) #f))) names)
      (check-equal? (file-exists? (path-expand ".gerbil/module-build/build.ss" root)) #f)
      (check-equal? (file-exists? (path-expand "yuanxu/object-family/syntax.scm" lib)) #f)
      (check-equal? (call-with-input-file unselected read-line) "; unselected output")
      (displayln "BUILD-PROCESS-REBUILD-OK targets=" (length spec)))
    (test-case "same fixture rejects package mismatch and changed admission inputs"
      (def result (.call InputChecks .run))
      (def output (.get result output))
      (display output)
      (check-equal? (.get result status) 0)
      (check-equal?
        (and (member
               (string-append "MODULE-OK "
                 (path-normalize
                   (path-expand "t/module-build-source-package-test.ss" (.get InputChecks directory))))
               (string-split output #\newline)) #t) #t)
      (check-equal? (and (string-contains output "HARNESS-OK") #t) #t)
      (check-equal? (and (member "OK" (string-split output #\newline)) #t) #t)
      (check-equal? (ormap (cut string-contains output <>)
                     '("ERROR CASE" "ERROR CHECK" "ERROR HARNESS" "Heap overflow" "Stack overflow")) #f))))
