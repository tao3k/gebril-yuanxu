;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-only Core qualification: direct source targets, unchanged SDK macro.
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/error Error? Error-message)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :gerbil/expander eval-syntax current-expander-context
                 make-top-context syntax->list core-read-module/sexp)
        (only-in :yuanxu/module-system/source/admission module-source-read))
(export module-source-spec-test)
(def root (getenv "CORE_QUALIFICATION_ROOT" #f))
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
  (parameterize ((current-expander-context (make-top-context)))
    (eval-syntax '(import :gerbil/core))
    (eval-syntax '(import (only-in :clan/poo/object .get)))
    (for-each eval-syntax (syntax->list (read-syntax-from-file path)))
    (eval-syntax `(import (only-in ,(path-expand "init.ss" root)
                                  yuanxu.init.exports)))
    (values (eval-syntax 'main) (eval-syntax '(.get yuanxu.init.exports std-make-spec))
            (eval-syntax '(.get yuanxu.init.exports admit-current)))))
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
    (if root
    (test-suite "User-owned standard build script consumes direct source spec"
      (test-case "real JsonSchema spec compile clean without source relocation"
        (check-equal? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))) #f)
        ;; The author-facing declaration stays byte-for-byte unchanged.
        (check-equal? (module-source-read (path-expand "modules/json-schema/interface.ss" root))
                      (module-source-read (path-expand "modules/json-schema/interface.ss" owner)))
        ;; Narrow only this isolated snapshot's retained manifest, not its build.ss.
        (write-source (path-expand "core-spec.ss" root)
          "(export core-spec) (def core-spec '(\"prelude\" \"utilities/algorithms\" \"object-types/contracts\" \"object-types/ports\" \"core-spec\"))\n")
        (let-values (((run spec current!) (script-at (path-expand "build.ss" root))))
          (displayln "SOURCE-SPEC-ROOT-IMPORTED") (force-output)
          (def printed (spec-of run))
          (displayln "SOURCE-SPEC-GRAPH-READY") (force-output)
          (def targets (spec retained))
          (def names (map (lambda (entry) (if (string? entry) entry (cadr entry))) targets))
          (check-equal? printed targets)
          (check-equal? (eq? targets (spec retained)) #t)
          (check-exception (spec '("object-types/contracts")) error?)
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
          ;; This acceptance check is explicit, outside the SDK main.
          (current!)
          (def lib (path-expand "lib" (getenv "GERBIL_PATH")))
          ;; An ordinary SDK package build must not mint a module-publication
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
          ;; The spec expression is evaluated for each SDK invocation.
          (for-each
            (lambda (control)
              (change-source (path-expand (car control) root)
                (lambda ()
                  (check-equal? (rejects? (cdr control) (lambda () (run "spec"))) #t)
                  ;; Guarded SDK invocation rejects before native compilation.
                  (check-equal? (rejects? (cdr control) (lambda () (run "compile"))) #t))))
            '(("build.ss" . "stale selected build input")
              ("core-spec.ss" . "stale prepared build source")
              ("gerbil.pkg" . "stale")
              ("prelude.ss" . "stale Module prelude source")
              ("module-system/source/role-forms.ss" . "compiler tool source changed")
              ("modules/json-schema/functional.ss" . "stale")
              ("object-types/contracts.ss" . "compiler tool source changed")))
          (check-equal? (spec-of run) targets)
          ;; A completed command supplies no continuing validity guarantee.
          (run "meta")
          (change-source (path-expand "modules/json-schema/config.ss" root)
            (lambda () (check-equal? (rejects? "stale" current!) #t)))
          (change-source (path-expand "init.ss" root)
            (lambda ()
              (check-equal? (rejects? "stale module scope generation"
                                     (lambda () (run "clean"))) #t)))
          (check-equal? (rejects? "module scope session was refused"
                                 (lambda () (run "spec"))) #t)
          (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
          (displayln "SOURCE-SPEC-TARGETS " (length targets)))))
    (begin
      (displayln "SKIP module-source-spec: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "module-source-spec (source-only opt-in)" (void)))))
