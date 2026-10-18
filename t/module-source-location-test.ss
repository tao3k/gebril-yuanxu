;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; SDK limitation controls: a source path is not an independent target identity.
(import :std/test
        (only-in :std/make make make-clean)
        (only-in :std/text/pregexp pregexp-match)
        (only-in :std/io/tempfile call-with-temporary-directory))
(export module-source-location-test)
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))
(def (with-probe test)
  (call-with-temporary-directory "source-location"
    (lambda (root)
      (def prefix (symbol->string (gensym 'source-location-)))
      (def prepared (path-expand "prepared" root))
      (def lib (path-expand "lib" root))
      (write-source (path-expand "gerbil.pkg" prepared)
        (call-with-output-string (lambda (out) (write (list 'package: (string->symbol prefix)) out))))
      (write-source (path-expand "probe.ss" prepared) "(export answer) (def answer 42)\n")
      (test root prefix prepared lib (path-expand "bin" root)))))
(def (build-probe spec source prefix lib bin)
  (make spec srcdir: source prefix: prefix libdir: lib bindir: bin parallelize: 1 optimize: #f))
(def (clean-probe spec source prefix lib bin)
  (make-clean spec srcdir: source prefix: prefix libdir: lib bindir: bin))
(def (compiled-probe prefix lib)
  (path-expand (string-append prefix "/probe.ssi") lib))
(def (missing-probe? thunk)
  (with-catch
    (lambda (exception)
      (if (pregexp-match "probe\\.ss"
            (call-with-output-string (lambda (out) (display-exception exception out)))) #t #f))
    (lambda () (thunk) #f)))
(def module-source-location-test
  (test-suite "Source-root and output-identity boundary"
    (test-case "relative target with the correct source root compiles and cleans"
      (with-probe
        (lambda (_root prefix prepared lib bin)
          (build-probe '("probe") prepared prefix lib bin)
          (check-equal? (file-exists? (compiled-probe prefix lib)) #t)
          (clean-probe '("probe") prepared prefix lib bin)
          (check-equal? (file-exists? (compiled-probe prefix lib)) #f))))
    (test-case "per-target srcdir metadata does not override the source root"
      (with-probe
        (lambda (root prefix prepared lib bin)
          (check-equal? (file-exists? (path-expand "probe.ss" prepared)) #t)
          (check-equal? (file-exists? (path-expand "probe.ss" root)) #f)
          (check-equal?
            (missing-probe?
              (lambda ()
                (build-probe (list (list 'gxc: "probe" (list 'srcdir: prepared)))
                              root prefix lib bin))) #t)
          (check-equal? (file-exists? (compiled-probe prefix lib)) #f))))
    (test-case "absolute source target does not preserve clean identity"
      (with-probe
        (lambda (root prefix prepared lib bin)
          (def spec (list (list 'gxc: (path-expand "probe" prepared))))
          (build-probe spec root prefix lib bin)
          ;; The compiler follows gerbil.pkg, but std/make predicts outputs
          ;; using the absolute target name. Clean therefore misses the output.
          (check-equal? (file-exists? (compiled-probe prefix lib)) #t)
          (clean-probe spec root prefix lib bin)
          (check-equal? (file-exists? (compiled-probe prefix lib)) #t))))
    (test-case "a relative prepared-directory target also changes the predicted identity"
      (with-probe
        (lambda (root prefix prepared lib bin)
          (def spec '((gxc: "prepared/probe")))
          (build-probe spec root prefix lib bin)
          (check-equal? (file-exists? (compiled-probe prefix lib)) #t)
          (check-equal? (file-exists?
            (path-expand (string-append prefix "/prepared/probe.ssi") lib)) #f)
          (clean-probe spec root prefix lib bin)
          (check-equal? (file-exists? (compiled-probe prefix lib)) #t))))))
