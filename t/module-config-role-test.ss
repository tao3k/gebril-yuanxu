;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander eval-syntax current-expander-context make-top-context)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source)
        (only-in :yuanxu/module-system/building/configuration-source yuanxu-configuration-source))
(export module-config-role-test)
(def (assert name value)
  (unless value (error "assertion failed" name))
  (displayln "ASSERT-OK " name) (force-output))
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (with-config text test)
  (call-with-temporary-directory "config-role"
    (lambda (root)
      (write-source (path-expand "gerbil.pkg" root)
        (string-append "(package: " (symbol->string (gensym 'config-role-)) ")"))
      (let* ((source (path-expand "config.ss" root))
             (wrapper (path-expand "wrapped.ss" root)))
        (write-source source text)
        (let (prepared (yuanxu-prepare-module-build-source source void))
          (call-with-output-file wrapper
            (lambda (port)
              (for-each (lambda (form) (write form port) (newline port))
                        (.get prepared compiler-forms))))
          (parameterize ((current-expander-context (make-top-context)))
            (eval-syntax `(import ,wrapper))
            (test source prepared)))))))
(def module-config-role-test
  (test-suite "Native config role defaults"
    (yuanxu-test-case "bare Config gets native POO and only its conventional export"
      (with-config
        "(def Private 41) (.def Base answer: Private) (.def (Config @ Base) answer: => 1+)"
        (lambda (_source _prepared)
          (assert 'native-poo-refinement (= (.get (eval-syntax 'Config) answer) 42))
          (assert 'private-binding-not-exported
            (with-catch (lambda (_e) #t) (lambda () (eval-syntax 'Private) #f)))
          (assert 'private-prototype-not-exported
            (with-catch (lambda (_e) #t) (lambda () (eval-syntax 'Base) #f))))))
    (yuanxu-test-case "native explicit headers remain valid without exporting all names"
      (with-config
        "prelude: :gerbil/core\n(import :clan/poo/object) (def Private 7) (def Config (.o answer: Private)) (export Config)"
        (lambda (_source _prepared)
          (assert 'explicit-native-header (= (.get (eval-syntax 'Config) answer) 7)))))
    (yuanxu-test-case "explicit POO extension imports retain their native binding"
      (with-config
        "(import (only-in :yuanxu/object-syntax/path-slots .o)) (def Config (.o answer: 9))"
        (lambda (_source _prepared)
          (assert 'explicit-object-syntax (= (.get (eval-syntax 'Config) answer) 9)))))
    (yuanxu-test-case "native inclusion retains the original config source location"
      (with-config
        "(import (only-in :std/source this-source-file)) (def Config (.o origin: (this-source-file)))"
        (lambda (source _prepared)
          (assert 'native-source-location
            (equal? (path-normalize (.get (eval-syntax 'Config) origin)) (path-normalize source))))))
    (yuanxu-test-case "unrelated config bindings do not acquire an unbound Config export"
      (with-config "(def Greeting \"hello\") (export Greeting)"
        (lambda (_source _prepared)
          (assert 'non-config-explicit-export (equal? (eval-syntax 'Greeting) "hello")))))
    (yuanxu-test-case "source identity and receiver-local values survive headerless revisions"
      (call-with-temporary-directory "config-role-revision"
        (lambda (root)
          (write-source (path-expand "gerbil.pkg" root)
            (string-append "(package: " (symbol->string (gensym 'config-revision-)) ")"))
          (let (source (path-expand "config.ss" root))
            (write-source source "(def Config (.o answer: 1))")
            (let (original (yuanxu-configuration-source source 'Config void))
              (assert 'original-source-retained (assoc source (.get original source-inputs)))
              (write-source source "(def Config (.o answer: 2))")
              (assert 'changed-source-rejected
                (with-catch (lambda (_e) #t) (lambda () ((.get original admit-current)) #f)))
              (let (updated (yuanxu-configuration-source source 'Config void))
                (assert 'updated-config (= (.get updated value answer) 2))
                (assert 'prior-config-cache-isolated (= (.get original value answer) 1))))))))))
