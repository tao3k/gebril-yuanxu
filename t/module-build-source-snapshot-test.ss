;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; SDK-only setup for a source-only Core qualification process.
(import :std/test (only-in :std/source this-source-file)
        (only-in :std/misc/ports read-all-as-string))
(export module-build-source-snapshot-test)
(def (copy-sources source target (top? #t))
  (for-each
    (lambda (name)
      (let* ((from (path-expand name source))
             (to (path-expand name target))
             (type (file-info-type (file-info from #f))))
        (cond
          ((eq? type 'directory)
           (unless (or (string-prefix? "." name)
                       (member name '("t" "design" "docs" "proofs" "packages")))
             (copy-sources from to #f)))
          ((and (eq? type 'regular)
                (or (string=? (path-extension name) ".ss") (string=? name "gerbil.pkg"))
                (not (and top?
                       (or (string=? name "bootstrap.ss")
                           (and (string=? name "build.ss")
                                (not (getenv "CORE_QUALIFICATION_BUILD_ENTRY" #f)))))))
           (create-directory* (path-directory to))
           (call-with-input-file from
             (lambda (in)
               (call-with-output-file to
                 (lambda (out) (display (read-all-as-string in) out)))))))))
    (directory-files source)))
(def module-build-source-snapshot-test
  (if (getenv "CORE_QUALIFICATION_ROOT" #f)
    (test-suite "Source-only isolated Core input"
      (test-case "stage current source without root bootstrap build entry or binaries"
        (def target (getenv "CORE_QUALIFICATION_ROOT"))
        (check-equal? (file-exists? target) #f)
        (copy-sources (path-expand ".." (path-directory (this-source-file))) target)
        (check-equal? (file-exists? (path-expand "init.ss" target)) #t)
        (check-equal? (file-exists? (path-expand "bootstrap.ss" target)) #f)
        (check-equal? (file-exists? (path-expand "build.ss" target))
                      (if (getenv "CORE_QUALIFICATION_BUILD_ENTRY" #f) #t #f))))
    (begin
      (displayln "SKIP source snapshot: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "Source-only snapshot (opt-in)" (void)))))
