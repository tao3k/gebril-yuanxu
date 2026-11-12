;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification only: exercise the Gerbil dispatcher, not a replacement protocol.
(import :std/test
        :std/build-script
        (only-in :std/io/tempfile call-with-temporary-directory))
(export module-build-entry-capture-test)

(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))

(def (entry-at entry spec lib bin package)
  (let ((this-source-file (lambda () entry)))
    (defbuild-script spec libdir: lib bindir: bin prefix: package
                     parallelize: 1 optimize: #f)
    main))

(def module-build-entry-capture-test
  (test-suite "Runtime build entry caller source capture"
    (test-case "spec compile and clean use the local source anchor"
      (call-with-temporary-directory "build-entry-capture"
        (lambda (root)
          (let* ((source (path-expand "source" root))
                 (lib (path-expand "lib" root))
                 (entry (path-expand "build.ss" source))
                 (package "build-entry-capture")
                 (run (entry-at entry '("probe") lib (path-expand "bin" root) package))
                 (output (path-expand (string-append package "/probe.ssi") lib)))
            (write-source (path-expand "probe.ss" source)
              (string-append "package: " package "\n(export answer) (def answer 42)\n"))
            (write-source entry "; runtime dispatcher source anchor\n")
            (let (text (call-with-output-string
                         (lambda (port)
                           (parameterize ((current-output-port port)) (run "spec")))))
              (check-equal? (call-with-input-string text read) '("probe")))
            (check-equal? (file-exists? output) #f)
            (run "compile")
            (check-equal? (file-exists? output) #t)
            (run "clean")
            (check-equal? (file-exists? output) #f)))))))
