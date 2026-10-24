;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :std/error Error?)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in "../module-system/building/artifacts.ss" clean-build-artifacts!))
(export module-build-artifact-clean-test)
(def (write-fixture path)
  (create-directory* (path-directory path))
  (call-with-output-file path (lambda (port) (display "keep" port))))
(def module-build-artifact-clean-test
  (test-suite "Selected native artifact cleanup"
    (yuanxu-test-case "partial native clean removes only the selected output family"
      (call-with-temporary-directory "selected-artifact-clean"
        (lambda (root)
          ;; .o1 is already gone: native clean left later generations behind.
          (def removed '("core/owned.o2" "core/owned.o23" "core/owned~Old~0.o7"
                         "core/owned.ssi" "core/owned.ssxi.ss" "core/owned.scm" "core/owned.c"
                         "static/core__owned.scm"))
          (def retained '("core/owned-other.o2" "core/unselected.o2" "core/owned.ss"
                          "static/core__unselected.scm"))
          (for-each (lambda (name) (write-fixture (path-expand name root)))
                    (append removed retained))
          (clean-build-artifacts! '(core/owned) root)
          (for-each (lambda (name) (check-equal? (file-exists? (path-expand name root)) #f)) removed)
          (for-each (lambda (name) (check-equal? (file-exists? (path-expand name root)) #t)) retained)
          (clean-build-artifacts! '(core/owned core/missing/subunit) root)
          (check-equal? (file-exists? (path-expand "core/owned.ss" root)) #t))))
    (yuanxu-test-case "symlinked outputs are refused without touching their target"
      (call-with-temporary-directory "selected-artifact-symlink"
        (lambda (root)
          (def target (path-expand "target" root))
          (def link (path-expand "core/owned.o2" root))
          (write-fixture target)
          (create-directory* (path-directory link))
          (create-symbolic-link target link)
          (check-exception (clean-build-artifacts! '(core/owned) root) Error?)
          (check-equal? (call-with-input-file target read-line) "keep")
          (check-equal? (file-exists? link) #t))))))
