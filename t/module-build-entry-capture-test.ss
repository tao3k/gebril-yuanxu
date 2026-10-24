;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification only: exercise the SDK dispatcher, not a replacement protocol.
(import :std/test
        :std/build-script
        (only-in :std/io/tempfile call-with-temporary-directory))
(export module-build-entry-capture-test)

(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))

(def (entry-at entry spec lib bin)
  (let ((this-source-file (lambda () entry)))
    (defbuild-script spec libdir: lib bindir: bin prefix: ""
                     parallelize: 1 optimize: #f)
    main))

(def module-build-entry-capture-test
  (test-suite "Native build entry caller source capture"
    (test-case "spec compile and clean use the local source anchor"
      (call-with-temporary-directory "build-entry-capture"
        (lambda (root)
          (let* ((source (path-expand "source" root))
                 (lib (path-expand "lib" root))
                 (entry (path-expand "build.ss" source))
                 (run (entry-at entry '("probe") lib (path-expand "bin" root)))
                 (output (path-expand "probe.ssi" lib)))
            (write-source (path-expand "probe.ss" source)
              "(export answer) (def answer 42)\n")
            (write-source entry "; native dispatcher source anchor\n")
            (let (text (call-with-output-string
                         (lambda (port)
                           (parameterize ((current-output-port port)) (run "spec")))))
              (check-equal? (call-with-input-string text read) '("probe")))
            (check-equal? (file-exists? output) #f)
            (run "compile")
            (check-equal? (file-exists? output) #t)
            (run "clean")
            (check-equal? (file-exists? output) #f)))))))
