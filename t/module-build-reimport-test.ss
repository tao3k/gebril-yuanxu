;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Gerbil-only entry: imports must happen inside the same-state regression control.
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/string/path path-force-extension)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :gerbil/expander eval-syntax core-import-module module-context-path
                 core-resolve-library-module-path current-expander-context
                 make-top-context import-module))
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
      (test-case "runtime resolver distinguishes a residual loader from the source module"
        (def lib (path-expand "lib" (getenv "GERBIL_PATH")))
        (def source (path-expand "object/syntax.ss" root))
        (def loader (path-expand "tao3k/yuanxu/object/syntax.scm" lib))
        (def original (load-path))
        ;; Run after the first compile/clean. Never delete or quarantine residue.
        (check-equal? (file-exists? loader) #t)
        (check-equal? (file-exists? (path-force-extension loader ".ssi")) #f)
        (dynamic-wind
          (lambda () (set-load-path! (cons lib (cons root original))))
          (lambda ()
            (check-equal? (core-resolve-library-module-path ':tao3k/yuanxu/object/syntax)
                          (path-normalize loader)))
          (lambda () (set-load-path! original)))
        ;; The production init entry owns source registration, not the launcher.
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax `(import ,(path-expand "init.ss" root))))
        (check-equal? (core-resolve-library-module-path ':tao3k/yuanxu/object/syntax)
                      (path-normalize source)))
      (test-case "source macro exports and use-site accessor bindings survive clean"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core :tao3k/yuanxu/object/syntax))
          (check-equal? (module-context-path (core-import-module ':tao3k/yuanxu/object/syntax))
                        (path-normalize (path-expand "object/syntax.ss" root)))
          (eval-syntax '(defpoo-object-family
                         (prototype Sample. sample? sample?)
                         (constructor make-sample (kind-value kind))
                         (accessors (sample-kind kind))
                         (projections)))
          (check-equal? (eval-syntax '(sample-kind (make-sample 'ready))) 'ready)))
      (test-case "real source objects import in a new process with residue intact"
        (parameterize ((current-expander-context (make-top-context)))
          (eval-syntax '(import :gerbil/core :tao3k/yuanxu/module-system/source/objects))
          (check-equal? (eval-syntax '(yuanxu-module-source-ref-kind
                                      (make-yuanxu-module-local-source "probe"))) 'local)))
      (test-case "same Graph spec compiles and cleans real JsonSchema again"
        (def owner (path-expand ".." (path-directory (this-source-file))))
        (check-equal? (source-text (path-expand "build.ss" root))
                      (source-text (path-expand "build.ss" owner)))
        (parameterize ((current-expander-context
                         (import-module (path-expand "build.ss" root) #t #t)))
          (def run (eval-syntax 'main))
          (eval-syntax '(import (only-in :tao3k/yuanxu/module-system/building/build-projection yuanxu-project-source-spec)))
          (def package
            (eval-syntax `(yuanxu-project-source-spec ,(path-expand "init.ss" root)
                           core-spec ,root ,(path-expand "build.ss" root))))
          (def current! (.get package admit-current))
          (def retained (eval-syntax 'core-spec))
          ;; Fail before any compile if the fixture is accidentally a full build.
          (def expected-retained
            '("prelude" "module-system/selection/init-syntax" "utilities/algorithms"
              "types/contracts" "types/ports" "core-spec"))
          (check-equal? retained expected-retained)
          (unless (equal? retained expected-retained)
            (error "same-state regression requires the bounded JsonSchema fixture"))
          (def targets (spec-of run))
          (def names (map (lambda (entry) (if (string? entry) entry (cadr entry))) targets))
          (check-equal? (spec-of run) targets)
          (check-equal? (equal? targets (spec-of run)) #t)
          (check-equal? (filter (lambda (name)
                                  (or (string-prefix? "modules/nix/" name)
                                      (string-prefix? "modules/opentofu/" name))) names) '())
          (def lib (path-expand "lib/tao3k/yuanxu" (getenv "GERBIL_PATH")))
          (run "compile")
          (current!)
          (for-each (lambda (name)
                      (check-equal? (file-exists? (path-expand (string-append name ".ssi") lib)) #t)) names)
          (run "clean")
          (current!)
          (for-each (lambda (name)
                      (check-equal? (file-exists? (path-expand (string-append name ".ssi") lib)) #f)) names)
          (check-equal? (file-exists? (path-expand "object/syntax.scm" lib)) #t)
          (check-equal? (file-exists? (path-expand ".gerbil/module-build" root)) #f)
          (displayln "REIMPORT-CYCLE-OK " phase " targets=" (length targets)))))
    (test-suite "Same-state reimport (opt-in)"
      (displayln "SKIP reimport: CORE_QUALIFICATION_ROOT is unset"))))
