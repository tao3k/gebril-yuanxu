;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata))
(export module-explicit-sources-test)
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (assert label value)
  (unless value (error "assertion failed" label))
  (displayln "ASSERT-OK " label) (force-output))
(def (rejects? pattern thunk)
  (with-catch
    (lambda (e) (and (pregexp-match pattern (call-with-output-string (cut display-exception e <>))) #t))
    (lambda () (thunk) #f)))
(def (fixture root)
  (write-source (path-expand "gerbil.pkg" root)
    (string-append "(package: " (symbol->string (gensym 'explicit-source-)) ")"))
  (for-each
   (lambda (entry)
     (let ((directory (path-expand (car entry) root)) (id (cdr entry)))
       (write-source (path-expand "types.ss" directory)
         "(import (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract) :clan/poo/object) (def Scope (yuanxu-predicate-contract 'scope object? (lambda (_v _c) '()))) (export Scope)")
       (write-source (path-expand "objects.ss" directory)
         "(import :clan/poo/object) (def Defaults (.o)) (export Defaults)")
       (write-source (path-expand "config.ss" directory) "(def Config (.o))")
       (write-source (path-expand "interface.ss" directory)
         (string-append "(.def Published identity: '" id " core: (.o requires: "
           (if (string=? id "app/main")
             "(.o Dependency: (.o module-id: 'core/dependency contract: Scope))" "(.o)")
           " scope-contract: Scope exports: (.o value: 42)) features: (.o))"))))
   '(("modules/app/main" . "app/main") ("contribution" . "core/dependency")))
  ;; Explicit binding must never fall back to this same-named invalid local tree.
  (write-source (path-expand "modules/core/dependency/interface.ss" root) "(((must-not-read")
  (write-source (path-expand "unselected/interface.ss" root) "(((must-not-read"))
(def module-explicit-sources-test
  (test-suite "Explicit authorization and native SourceRef bindings"
    (yuanxu-test-case "required dependencies must be declared and cannot be disabled"
      (call-with-temporary-directory "explicit-denied"
        (lambda (root)
          (fixture root)
          (let (init (path-expand "init.ss" root))
            (write-source init "(yuanxu! mode: explicit :app (main))")
            (assert 'undeclared-required-rejected
              (rejects? "required module not explicitly declared"
                (lambda () (.get (yuanxu-load-modules init) selected-graph))))
            (write-source init "(yuanxu! mode: explicit :core (dependency @ \"./missing\" disable: #t) :app (main))")
            (assert 'disabled-required-rejected-before-source-read
              (rejects? "required module disabled"
                (lambda () (.get (yuanxu-load-modules init) selected-graph))))))))
    (yuanxu-test-case "one explicit source tree admits physical sources without copies or fallback"
      (call-with-temporary-directory "explicit-source-tree"
        (lambda (root)
          (fixture root)
          (let (init (path-expand "init.ss" root))
            (write-source init "(yuanxu! mode: explicit :core (dependency @ \"./contribution\") :app (main) :unused (bomb @ \"./unselected\" disable: #t))")
            (def view (yuanxu-load-modules init))
            (assert 'declared-dependency-order
              (equal? (.get view dependency-order) '(core/dependency app/main)))
            (assert 'bound-module-scope (= (.get view modules core dependency value) 42))
            (def source (.get (car (.get view selected-records)) source))
            (def metadata (yuanxu-module-source-ref-metadata source))
            (assert 'native-explicit-source-ref (eq? (cdr (assq 'source-binding metadata)) 'explicit))
            (assert 'physical-owner-retained
              (equal? (path-normalize (cdr (assq 'module-root metadata)))
                      (path-normalize (path-expand "contribution" root))))
            (assert 'undeclared-scope-not-exposed (not (.slot? (.get view modules) 'unselected)))
            (def graph (.get view build-graph))
            (write-source (path-expand "contribution/config.ss" root) "(def Config (.o changed: #t))")
            (assert 'external-source-currentness-rejected
              (rejects? "stale|changed|refused" (lambda () ((.get graph admit-current)))))))))
    (yuanxu-test-case "auto discovery exposes explicitly bound origins through the same tree"
      (call-with-temporary-directory "auto-source-tree"
        (lambda (root)
          (fixture root)
          (delete-file (path-expand "modules/core/dependency/interface.ss" root))
          (delete-directory (path-expand "modules/core/dependency" root))
          (delete-directory (path-expand "modules/core" root))
          (let (init (path-expand "init.ss" root))
            (write-source init "(yuanxu! mode: auto :core (dependency @ \"./contribution\"))")
            (let (view (yuanxu-load-modules init))
              (assert 'auto-bound-virtual-namespace (= (.get view modules core dependency value) 42))
              (assert 'auto-local-demand-retained (= (.get view modules app main value) 42)))))))
    (yuanxu-test-case "missing explicit origin cannot use a matching local module"
      (call-with-temporary-directory "explicit-no-fallback"
        (lambda (root)
          (fixture root)
          (let (init (path-expand "init.ss" root))
            (write-source init "(yuanxu! mode: explicit :core (dependency @ \"./missing\") :app (main))")
            (assert 'missing-origin-rejected
              (rejects? "module source is not a directory"
                (lambda () (.get (yuanxu-load-modules init) selected-graph))))))))))
