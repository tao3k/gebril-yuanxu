;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source preparation is fixture data; Gerbil owns the executable build entry.
(import :std/test
        (only-in :clan/poo/object .get .call)
        (only-in :std/source this-source-file)
        (only-in :std/misc/ports read-all-as-string)
        (only-in "./qualification/module-testing/fixtures.ss" selection-fixture))
(export module-build-source-snapshot-test test-setup! test-cleanup!)
(def owner (path-expand ".." (path-directory (this-source-file))))
(def Fixture (selection-fixture owner))
(def resource #f)
(def (test-setup!) (set! resource (.call Fixture .acquire)))
(def (test-cleanup!)
  (when resource
    (begin0 (.call Fixture .release resource) (set! resource #f))))
(def module-build-source-snapshot-test
  (test-suite "Source-only snapshot uses the ordinary package entry"
    (test-case "cold data retains the real build entry and excludes Core binaries"
      (def root (.get resource root))
      (def state (.get resource state))
      (check-equal? (.get resource cold) #t)
      (for-each
        (lambda (name) (check-equal? (file-exists? (path-expand name root)) #t))
        '("gerbil.pkg" "init.ss" "build.ss" "prelude.ss"
          "modules/json-schema/interface.ss"))
      (check-equal?
        (call-with-input-file (path-expand "build.ss" root) read-all-as-string)
        (call-with-input-file (path-expand "build.ss" owner) read-all-as-string))
      (for-each
        (lambda (name) (check-equal? (file-exists? (path-expand name root)) #f))
        '("bootstrap.ss" "run.ss" ".git" "t" "dev"))
      (check-equal? (file-exists? (path-expand "lib/yuanxu" state)) #f)
      (check-equal? (file-exists? (path-expand "lib/tao3k/yuanxu" state)) #f))))
