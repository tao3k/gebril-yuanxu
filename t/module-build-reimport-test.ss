;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; SDK-only entry: imports must happen inside the same-state regression control.
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/string/path path-force-extension)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil/expander eval-syntax core-import-module module-context-path
                 core-resolve-library-module-path current-expander-context
                 make-top-context syntax->list))
(export module-build-reimport-test)
(def root (getenv "CORE_QUALIFICATION_ROOT" #f))
(def phase (getenv "CORE_REIMPORT_PHASE" "cycle"))
(def (source-text path)
  (call-with-input-file path read-all-as-string))
(def (spec-of run)
  (call-with-input-string
    (call-with-output-string
      (lambda (out) (parameterize ((current-output-port out)) (run "spec")))) read))
(def module-build-reimport-test
  (if root
    (test-suite "Cross-process rebuild in the same compiled and cleaned state"
      (test-case "native resolver distinguishes a residual loader from the source module"
        (def lib (path-expand "lib" (getenv "GERBIL_PATH")))
        (def source (path-expand "object-family/syntax.ss" root))
        (def loader (path-expand "yuanxu/object-family/syntax.scm" lib))
        (def original (load-path))
        ;; Run after the first compile/clean. Never delete or quarantine residue.
        (check-equal? (file-exists? loader) #t)
        (check-equal? (file-exists? (path-force-extension loader ".ssi")) #f)
        (dynamic-wind
          (lambda () (set-load-path! (cons lib (cons root original))))
          (lambda ()
            (check-equal? (core-resolve-library-module-path ':yuanxu/object-family/syntax)
                          (path-normalize loader)))
          (lambda () (set-load-path! original)))
        ;; The production init entry owns source registration, not the launcher.
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax `(import ,(path-expand "init.ss" root))))
        (check-equal? (core-resolve-library-module-path ':yuanxu/object-family/syntax)
                      (path-normalize source)))
      (test-case "source macro exports and use-site accessor bindings survive clean"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core :yuanxu/object-family/syntax))
          (check-equal? (module-context-path (core-import-module ':yuanxu/object-family/syntax))
                        (path-normalize (path-expand "object-family/syntax.ss" root)))
          (eval-syntax '(defpoo-object-family
                         (prototype Sample. sample? sample?)
                         (constructor make-sample (kind-value kind))
                         (accessors (sample-kind kind))
                         (projections)))
          (check-equal? (eval-syntax '(sample-kind (make-sample 'ready))) 'ready)))
      (test-case "real source objects import in a new process with residue intact"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core :yuanxu/module-system/source/objects))
          (check-equal? (eval-syntax '(yuanxu-module-source-ref-kind
                                      (make-yuanxu-module-local-source "probe"))) 'local)))
      (test-case "same Graph spec compiles and cleans real JsonSchema again"
        (def owner (path-expand ".." (path-directory (this-source-file))))
        (check-equal? (source-text (path-expand "build.ss" root))
                      (source-text (path-expand "build.ss" owner)))
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core))
          (eval-syntax '(import (only-in :clan/poo/object .get)))
          (for-each eval-syntax (syntax->list (read-syntax-from-file (path-expand "build.ss" root))))
          (eval-syntax `(import (only-in ,(path-expand "init.ss" root)
                                        yuanxu.init.exports )))
          (def run (eval-syntax 'main))
          (def spec (eval-syntax '(.get yuanxu.init.exports std-make-spec)))
          (def current! (eval-syntax '(.get yuanxu.init.exports admit-current)))
          (def retained (eval-syntax 'core-spec))
          ;; Fail before any compile if the fixture is accidentally a full build.
          (check-equal? retained '("prelude" "utilities/algorithms" "object-types/contracts" "object-types/ports" "core-spec"))
          (unless (equal? retained '("prelude" "utilities/algorithms" "object-types/contracts" "object-types/ports" "core-spec"))
            (error "same-state regression requires the bounded JsonSchema fixture"))
          (def targets (spec retained))
          (def names (map (lambda (entry) (if (string? entry) entry (cadr entry))) targets))
          (check-equal? (spec-of run) targets)
          (check-equal? (eq? targets (spec retained)) #t)
          (check-equal? (filter (lambda (name)
                                  (or (string-prefix? "modules/nix/" name)
                                      (string-prefix? "modules/opentofu/" name))) names) '())
          (def lib (path-expand "lib/yuanxu" (getenv "GERBIL_PATH")))
          (run "compile")
          (current!)
          (for-each (lambda (name)
                      (check-equal? (file-exists? (path-expand (string-append name ".ssi") lib)) #t)) names)
          (run "clean")
          (current!)
          (for-each (lambda (name)
                      (check-equal? (file-exists? (path-expand (string-append name ".ssi") lib)) #f)) names)
          (check-equal? (file-exists? (path-expand "object-family/syntax.scm" lib)) #t)
          (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
          (displayln "REIMPORT-CYCLE-OK " phase " targets=" (length targets)))))
    (test-suite "Same-state reimport (opt-in)"
      (displayln "SKIP reimport: CORE_QUALIFICATION_ROOT is unset"))))
