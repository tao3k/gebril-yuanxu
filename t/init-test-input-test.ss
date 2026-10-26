;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Init owns test source selection and the explicit native compile boundary.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/source this-source-file)
        (only-in "../init.ss" yuanxu.init.exports))
(export init-test-input-test)

;; Rewrite only fixture bytes; assertions stay outside the exception catcher.
(def (put path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (refuses? operation)
  (with-catch (lambda (_) #t) (lambda () (operation) #f)))
(def tests (.get yuanxu.init.exports tests))
(def init-test-input-test
  (test-suite "Init-owned explicit and directory test inputs"
    (test-case "native support retains its package compiler declaration"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-temporary-directory (path-expand "t/qualification/native-options-" root)
        (lambda (directory)
          ;; Keep support in the real package root: native Make must use the
          ;; package's identity and output placement, not a fabricated namespace.
          (def support (path-expand "support.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (def config (path-expand "compiler-input.txt" directory))
          (def target (path-strip-extension
                        (substring support
                          (string-length (string-append (path-strip-trailing-directory-separator root) "/"))
                          (string-length support))))
          (put support
            "(import (only-in :std/ffi C-declare))\n(C-declare \"#ifndef YUANXU_NATIVE_OPTIONS_PROBE\\n#error missing native compiler option\\n#endif\\n\")\n(export native-value) (def native-value 7)\n")
          (put file
            (string-append "(import :std/test :yuanxu/" target
              ") (export probe-test)\n(def probe-test (test-suite \"native compiler options\" (test-case \"real compiled support\" (check-equal? native-value 7))))\n"))
          (put config "-DYUANXU_NATIVE_OPTIONS_PROBE")
          (def demand
            (.call tests .for-files (list file) (list config)
              (list (list 'gxc: target "-cc-options" "-DYUANXU_NATIVE_OPTIONS_PROBE"))))
          (check-equal? (.get (.call demand .run) status) 0)
          ;; A conflicting declaration cannot silently select arbitrary flags.
          (def duplicate
            (.call tests .for-files (list file) (list config)
              (list (list 'gxc: target "-cc-options" "-DYUANXU_NATIVE_OPTIONS_PROBE")
                    (list 'gxc: target "-cc-options" "-DOTHER"))))
          (check-exception (.call duplicate .compile) error?)
          (put config "changed compiler input")
          (check-exception (.call demand .compile) error?))))
    (test-case "init compile prepares native support without running the Case"
      (call-with-temporary-directory "init-compile-"
        (lambda (directory)
          (def file (path-expand "sample-test.ss" directory))
          (def marker (path-expand "case-ran" directory))
          (put (path-expand "gerbil.pkg" directory) "(package: init-compile-fixture)\n")
          (put file
            (string-append
              "(import :std/test) (export sample-test)\n"
              "(def sample-test (test-suite \"compile boundary\" (test-case \"runtime only\" "
              "(call-with-output-file " (object->string marker)
              " (lambda (port) (display \"ran\" port))))))\n"))
          (def demand (.call tests .for-files (list file)))
          (def prepared (.call demand .compile))
          (check-equal? (eq? (.get prepared source) (.get demand source)) #t)
          (check-equal? (file-exists? marker) #f)
          ;; An inherited compile method cannot drop its declared compiler.
          (check-exception (.call (.cc (.get demand execution) build: #f) .compile) error?)
          (put file "(import :std/test) (export sample-test) (def sample-test (test-suite \"changed\"))")
          (check-exception (.call demand .compile) error?))))
    (test-case "external inputs invalidate an inert explicit demand"
      (call-with-temporary-directory "init-input-"
        (lambda (directory)
          (def file (path-expand "sample-test.ss" directory))
          (def input (path-expand "support.txt" directory))
          (put file "(export value)\n(def value 1)\n")
          (put input "original")
          (def demand (.call tests .for-files (list file) (list input)))
          (check-equal? (.get demand spec) (list file))
          (check-equal? (.slot? demand '.compile) #t)
          (check-equal? (.ref/cached demand 'selected-graph) #f)
          ((.get demand admit-current))
          (put input "changed")
          (check-equal? (refuses? (.get demand admit-current)) #t))))
    (test-case "excluded subtrees stay outside admission; new peers invalidate it"
      (call-with-temporary-directory "init-directory-"
        (lambda (directory)
          (def file (path-expand "sample-test.ss" directory))
          (def excluded (path-expand "excluded" directory))
          (create-directory excluded)
          (put file "original")
          (put (path-expand "broken-test.ss" excluded) "(")
          (def demand (.call tests .for-directory directory '("excluded")))
          (check-equal? (.get demand spec) (list file))
          ((.get demand admit-current))
          (put (path-expand "broken-test.ss" excluded) "different excluded bytes")
          (check-equal? (refuses? (.get demand admit-current)) #f)
          (put (path-expand "later-test.ss" directory) "new peer")
          (check-equal? (refuses? (.get demand admit-current)) #t))))))
