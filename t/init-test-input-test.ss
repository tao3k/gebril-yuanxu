;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Init owns test source selection and the explicit native compile boundary.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/source this-source-file)
        (only-in "./qualification/module-init/fixture.ss"
                 call-with-prepared-package prepared-package-tests)
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
    (test-case "different Suites share support products but execute separate verdicts"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-prepared-package (path-expand "t/qualification/native-shared" root)
        (lambda (directory)
          (def tests (prepared-package-tests directory))
          (def support (path-expand "support.ss" directory))
          (def first (path-expand "first-test.ss" directory))
          (def second (path-expand "second-test.ss" directory))
          (def target "support")
          ;; Both Suites import the identical package-owned compiled module.
          ;; Their distinct assertions must still run in independent harnesses.
          (def (suite file name expected)
            (put file
              (string-append "(import :std/test :yuanxu-native-shared/" target ") (export " name "-test)\n"
                "(def " name "-test (test-suite \"" name "\" (test-case \"own verdict\" "
                "(check-equal? value " (number->string expected) "))))\n")))
          (suite first "first" 7)
          (suite second "second" 7)
          (def a (.call tests .for-files (list first)))
          (def b (.call tests .for-files (list second)))
          (def directory-a (.get (.get a build) output-directory))
          (check-equal? directory-a (.get (.get b build) output-directory))
          (check-equal? (.ref/cached (.get a source) 'selected-graph) #f)
          (check-equal? (.get (.call a .run) status) 0)
          ;; Explicit native support must not acquire unrelated business
          ;; selection merely to mint its own compiler issuance generation.
          (check-equal? (.ref/cached (.get a source) 'selected-graph) #f)
          ;; Identical support products do not let another source borrow this
          ;; Script's compiler association, even before selection is acquired.
          (check-exception
            (.call (.cc (.get a execution) 'source (.get b source)) .compile) error?)
          (def product (path-expand (string-append "yuanxu-native-shared/" target ".o1") directory-a))
          (def modified (time->seconds (file-info-last-modification-time (file-info product))))
          (.call b .compile)
          (check-equal? (.get (.call b .run) status) 0)
          (check-equal? (time->seconds (file-info-last-modification-time (file-info product))) modified)
          ;; Changing only a Suite must refuse its old demand. A fresh demand
          ;; may reuse support, but must execute the new (failing) assertion.
          (suite second "second" 8)
          (check-exception (.call b .compile) error?)
          (def changed (.call tests .for-files (list second)))
          (check-equal? directory-a (.get (.get changed build) output-directory))
          (check-exception (.call changed .run) error?)
          ;; Support changes invalidate the product and every old consumer.
          (put support "(export value) (def value 8)\n")
          (check-exception (.call a .compile) error?)
          (def new-support (.call tests .for-files (list first)))
          (check-equal? (equal? directory-a (.get (.get new-support build) output-directory)) #f))))
    (test-case "a selected Suite used for-syntax remains a compiler input"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-temporary-directory (path-expand "t/qualification/macro-support-" root)
        (lambda (directory)
          (def helper (path-expand "helper-test.ss" directory))
          (def support (path-expand "support.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (put helper "(export value) (def value 7)\n")
          (put support "(import (for-syntax \"./helper-test.ss\")) (export answer) (def answer 7)\n")
          (put file "(import \"./support.ss\") (export result) (def result answer)\n")
          (def demand (.call tests .for-files (list helper file)))
          (def inputs (.get (.get demand build) source-inputs))
          ;; Excluding every selected file would incorrectly drop this real
          ;; compile-time dependency. The native graph must retain its bytes.
          (check-equal? (and (assoc (path-normalize helper) inputs) #t) #t)
          (put helper "(export value) (def value 8)\n")
          (check-exception ((.get (.get demand build) admit-current)) error?))))
    (test-case "native support retains its package compiler declaration"
      (def root (path-expand ".." (path-directory (this-source-file))))
      (call-with-prepared-package (path-expand "t/qualification/native-options" root)
        (lambda (directory)
          (def tests (prepared-package-tests directory))
          ;; The Just phase compiled this real, independent Gerbil package.
          ;; The native C declaration still rejects a missing compiler option.
          (def support (path-expand "support.ss" directory))
          (def file (path-expand "probe-test.ss" directory))
          (def config (path-expand "compiler-input.txt" directory))
          (def target "support")
          (put file
            (string-append "(import :std/test :yuanxu-native-options/" target
              ") (export probe-test)\n(def probe-test (test-suite \"native compiler options\" (test-case \"real compiled support\" (check-equal? native-value 7))))\n"))
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
