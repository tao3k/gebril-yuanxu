;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-only Core qualification: direct source targets, standard Gerbil macro.
(import :std/test
        (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        (only-in :clan/poo/object .get .call)
        (only-in "./qualification/module-testing/fixtures.ss" selection-fixture)
        (only-in :std/source this-source-file)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander eval-syntax current-expander-context
                 import-module core-read-module/sexp)
        (only-in :yuanxu/module-system/source/admission module-source-read))
(export module-source-spec-test test-setup! test-cleanup!)
(def Fixture (selection-fixture (path-expand ".." (path-directory (this-source-file)))))
(def resource #f)
(def root #f)
(def (test-setup!)
  (set! resource (.call Fixture .acquire))
  (set! root (.get resource root)))
(def (test-cleanup!)
  (when resource
    (begin0 (.call Fixture .release resource)
      (set! resource #f) (set! root #f))))
(def owner (path-expand ".." (path-directory (this-source-file))))
(def (compiled-path root lib name)
  (let-values (((_prelude identity _namespace _body)
                (core-read-module/sexp (path-expand (string-append name ".ss") root))))
    (path-expand (string-append (symbol->string identity) ".ssi") lib)))
(def retained '("prelude" "utilities/algorithms" "object-types/contracts" "object-types/ports" "core-spec"))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (out) (display text out))))
(def (script-at path)
  (parameterize ((current-expander-context (import-module path #t #t)))
    (def build (yuanxu-project-source-spec (path-expand "init.ss" root)
                  (eval-syntax 'core-spec) root path))
    (values (eval-syntax 'main) (eval-syntax 'yuanxu.init.exports) build)))
(def (spec-of run)
  (call-with-input-string
    (call-with-output-string
      (lambda (out) (parameterize ((current-output-port out)) (run "spec")))) read))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (e)
      (if (and (Error? e) (pregexp-match pattern (Error-message e))) #t
          (begin (display-exception e) #f)))
      (lambda () (thunk) #f)))
  (def (change-source path test)
    (let (text (module-source-read path))
      (dynamic-wind
        (lambda () (write-source path (string-append text "\n;; changed input\n")))
        test
        (lambda () (write-source path text)))))
  (def module-source-spec-test
    (test-suite "User-owned standard build script consumes direct source spec"
      (test-case "real JsonSchema spec compile clean without source relocation"
        (check-equal? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))) #f)
        ;; The author-facing declaration stays byte-for-byte unchanged.
        (check-equal? (module-source-read (path-expand "modules/json-schema/interface.ss" root))
                      (module-source-read (path-expand "modules/json-schema/interface.ss" owner)))
        ;; Narrow only this isolated snapshot's retained manifest, not its build.ss.
        (write-source (path-expand "core-spec.ss" root)
          "(export core-spec) (def core-spec '(\"prelude\" \"utilities/algorithms\" \"object-types/contracts\" \"object-types/ports\" \"core-spec\"))\n")
        (let-values (((run exports build) (script-at (path-expand "build.ss" root))))
          (def current! (.get build admit-current))
          (displayln "SOURCE-SPEC-ROOT-IMPORTED") (force-output)
          (def printed (spec-of run))
          (displayln "SOURCE-SPEC-GRAPH-READY") (force-output)
          (def module-targets (.get exports std-make-spec))
          (def targets (append module-targets retained))
          (def names (map (lambda (entry) (if (string? entry) entry (cadr entry))) targets))
          (check-equal? printed targets)
          (check-equal? (eq? module-targets (.get exports std-make-spec)) #t)
          (check-exception (.call build .admit-spec '((gxc: "object-types/contracts"))) error?)
          (check-equal? (filter (lambda (name)
                                  (or (string-prefix? "modules/nix/" name)
                                      (string-prefix? "modules/opentofu/" name))) names) '())
          (for-each (lambda (name)
                      (check-equal? (length (filter (cut equal? <> name) names)) 1)
                      (check-equal? (file-exists? (path-expand (string-append name ".ss") root)) #t))
                    names)
          (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
          (check-equal? (file-exists? (path-expand "bootstrap.ss" root)) #f)
          (run "compile")
          ;; This acceptance check is explicit, outside the STD-generated main.
          (current!)
          (def lib (path-expand "lib" (getenv "GERBIL_PATH")))
          ;; An ordinary Gerbil package build must not mint a module-publication
          ;; receipt. Explicit graph compilation is tested by publication cases.
          (check-equal?
            (filter (cut string-prefix? ".yuanxu-build-issuance-" <>)
              (directory-files (list path: lib ignore-hidden: #f))) '())
          (for-each (lambda (name)
                      (check-equal? (file-exists?
                        (compiled-path root lib name)) #t)) names)
          (run "clean")
          (current!)
          (for-each (lambda (name)
                      (check-equal? (file-exists?
                        (compiled-path root lib name)) #f)) names)
          ;; The standard list is data, not a continuing publication permit.
          ;; Preserve stale-input refusals at the explicit compilation boundary.
          (for-each
            (lambda (control)
              (change-source (path-expand (car control) root)
                (lambda ()
                  (check-equal? (rejects? (cdr control) current!) #t)
                  (def entered? #f)
                  (check-equal? (rejects? (cdr control)
                    (lambda ()
                      (.call build .compile lib
                        (lambda () (set! entered? #t) (run "compile"))))) #t)
                  (check-equal? entered? #f))))
            '(("build.ss" . "stale selected build input")
              ("core-spec.ss" . "stale prepared build source")
              ("gerbil.pkg" . "compiler tool source changed")
              ("prelude.ss" . "compiler tool source changed")
              ("module-system/source/role-forms.ss" . "compiler tool source changed")
              ("modules/json-schema/functional.ss" . "compiler tool source changed")
              ("object-types/contracts.ss" . "compiler tool source changed")))
          (check-equal? (spec-of run) targets)
          ;; A completed command supplies no continuing validity guarantee.
          (run "meta")
          (change-source (path-expand "modules/json-schema/config.ss" root)
            (lambda () (check-equal? (rejects? "stale" current!) #t)))
          (change-source (path-expand "init.ss" root)
            (lambda ()
              (check-equal? (rejects? "stale module scope generation"
                                     (lambda ()
                                       (.call build .with-clean-outputs
                                         (lambda () (run "clean"))))) #t)))
          (check-equal? (rejects? "module scope session was refused"
                                 current!) #t)
          (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
          (displayln "SOURCE-SPEC-TARGETS " (length targets))))))
