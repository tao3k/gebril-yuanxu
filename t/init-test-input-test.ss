;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test inputs stay source-bound without compiling or executing a nested suite.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
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
