;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declarative Ops scripts; each child establishes its own source context.
(import :std/test :clan/poo/object
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :tao3k/yuanxu/ops/func run-script)
        (only-in :tao3k/yuanxu/ops/progress execution-progress!)
        (only-in :tao3k/yuanxu/module-system/building/products selected-output-source-directory)
        (only-in :gerbil/expander core-read-module/sexp)
        "./qualification/module-bootstrap/objects.ss")
(export module-build-process-test)
(def completed-build-actions 0)
(def (build-command script action)
  (displayln "BUILD-PROCESS " action) (force-output)
  ;; Forward actual compiler output while retaining the captured result for
  ;; assertions. The outer Harness must observe child progress as it occurs.
  (def execution
    (if (member action '("compile" "clean"))
      (.cc script 'environment
        (.+ (.get script environment)
            (.o GERBIL_BUILD_VERBOSE: (if (equal? action "clean") "2" "1"))))
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
  ;; Spec and hot builds may emit no compiler event. Their successful natural
  ;; return is progress. A failed child cannot advance it.
  (set! completed-build-actions (1+ completed-build-actions))
  (execution-progress! 'source-bootstrap-action completed-build-actions)
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
(def (check-clean-output output root lib names)
  (check-equal? (string-contains output "... compile ") #f)
  (check-equal? (string-contains output "... execute compile job ") #f)
  ;; Assert the standard compiler's actual products below. The removed
  ;; Yuanxu CLI adapter's BUILD-ACCOUNT text is not a Gerbil contract.
  (def removal-prefix "... remove ")
  (def removed-interfaces
    (filter-map
      (lambda (line)
        (and (string-prefix? removal-prefix line)
             (string-suffix? ".ssi" line)
             (path-normalize (substring line (string-length removal-prefix)
                                       (string-length line)))))
      (string-split output #\newline)))
  (def expected-interfaces
    (map (lambda (name)
           (let-values (((path _identity) (compiled-path root lib name)))
             (check-equal? (file-exists? path) #f)
             (path-normalize path)))
         names))
  (check-equal? (list-sort string<? removed-interfaces)
                (list-sort string<? expected-interfaces)))
(def module-build-process-test
  (test-suite "Normal build script registers its own source package"
    (test-case "compile clean and new-process rebuild share one fixture and output identities"
      (def root (.get Fixture root))
      (def lib (path-expand "lib" (.get Fixture state)))
      (displayln "SOURCE-BUILD-FIXTURE " root) (force-output)
      (check-equal? (.slot? (.get Build environment) 'GERBIL_BUILD_CORES) #f)
      (displayln "BUILD-PROCESS-CORES " (getenv "GERBIL_BUILD_CORES" #f))
      (force-output)
      (when (.get Fixture cold) (check-equal? (file-exists? (path-expand "tao3k/yuanxu" lib)) #f))
      (def spec (call-with-input-string (build-command Build "spec") read))
      (def names (map (lambda (target) (if (string? target) target (cadr target))) spec))
      ;; Every emitted source must build exactly once. Prerequisite library
      ;; imports do not need a second declaration in this selected package.
      (check-equal? (length names) (length (delete-duplicates/hash names)))
      (for-each
        (lambda (target) (check-equal? (and (member target names) #t) #t))
        '("prelude" "modules/example/interface" "modules/example/types"
          "modules/example/objects" "modules/example/config"))
      (check-equal? (member "module-system/building/artifacts" names) #f)
      (def cold-output (build-command Build "compile"))
      (def recorded-interface
        (path-expand "tao3k/yuanxu/modules/example/interface.ss" (selected-output-source-directory lib)))
      (check-equal? (file-exists? recorded-interface) #f)
      (def bootstrap-targets
        '("... compile module-system/selection/init-syntax" "... compile prelude"))
      (check-equal? (filter (cut member <> bootstrap-targets) (string-split cold-output #\newline))
                    bootstrap-targets)
      (def first-identities (output-identities root lib names))
      ;; The language and libraries use one package prefix. A fresh process
      ;; must reuse its real products without compiling an alias.
      (def prelude-products
        (list (path-expand "tao3k/yuanxu/prelude.ssi" lib)
              (path-expand "static/tao3k__yuanxu__prelude.scm" lib)))
      (def (product-times)
        (map (lambda (path)
               (time->seconds (file-info-last-modification-time (file-info path))))
             prelude-products))
      (def first-times (product-times))
      (def hot-output (build-command Build "compile"))
      (check-equal? (file-exists? recorded-interface) #f)
      (check-equal? (string-contains hot-output "... compile ") #f)
      (check-equal? (string-contains hot-output "... execute compile job ") #f)
      (check-equal? (product-times) first-times)
      (check-equal? (file-exists? (path-expand "yuanxu/prelude.ssi" lib)) #f)
      (check-equal? (file-exists? (path-expand "legacy/prelude.ssi" lib)) #f)
      (check-equal? (file-exists? (path-expand "static/legacy__prelude.scm" lib)) #f)
      ;; Ordinary Make cleans the declared static source. Keep a separate,
      ;; unselected sentinel so cleanup isolation is checked independently.
      (def unselected (path-expand "tao3k/yuanxu/object/unselected-output.scm" lib))
      (call-with-output-file unselected (cut display "; unselected output\n" <>))
      (check-clean-output (build-command Build "clean") root lib names)
      (check-equal? (file-exists? (path-expand "static/tao3k__yuanxu__object__syntax.scm" lib)) #f)
      (check-equal? (call-with-input-file unselected read-line) "; unselected output")
      ;; This must compile again, not merely print a new-process specification.
      ;; The same Script retains the exact source directory and GERBIL_PATH.
      (build-command Build "compile")
      (check-equal? (output-identities root lib names) first-identities)
      (check-clean-output (build-command Build "clean") root lib names)
      (check-equal? (file-exists? (path-expand ".gerbil/module-build/build.ss" root)) #f)
      (check-equal? (file-exists? (path-expand "static/tao3k__yuanxu__object__syntax.scm" lib)) #f)
      (check-equal? (call-with-input-file unselected read-line) "; unselected output")
      (displayln "BUILD-PROCESS-REBUILD-OK targets=" (length spec)))))
