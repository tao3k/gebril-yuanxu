;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Gerbil limitation controls: a source path is not an independent target identity.
(import :std/test
        (only-in :std/make make make-clean)
        (only-in :yuanxu/module-system/building/artifacts clean-build-artifacts!)
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
(def (probe-compile-events spec source prefix lib bin)
  (def output (open-output-string))
  (parameterize ((current-output-port output)) (build-probe spec source prefix lib bin))
  (call-with-input-string (get-output-string output)
    (lambda (port)
      (let loop ((events '()))
        (def line (read-line port))
        (cond ((eof-object? line) (reverse events))
              ((string-prefix? "... compile " line)
               (loop (cons (substring line 12 (string-length line)) events)))
              (else (loop events)))))))
(def (compiled-probe prefix lib)
  (path-expand (string-append prefix "/probe.ssi") lib))
(def (missing-probe? thunk)
  (with-catch
    (lambda (exception)
      (if (pregexp-match "probe\\.ss"
            (call-with-output-string (lambda (out) (display-exception exception out)))) #t #f))
    (lambda () (thunk) #f)))
(def (with-cross-package-view test)
  (call-with-temporary-directory "cross-package-view"
    (lambda (root)
      (def producer (symbol->string (gensym 'source-producer-)))
      (def consumer (symbol->string (gensym 'source-consumer-)))
      (def view (path-expand "view" root))
      (def lib (path-expand "lib" root))
      (def bin (path-expand "bin" root))
      (def producer-source (path-expand "producer/value.ss" root))
      (def consumer-source (path-expand "consumer/main.ss" root))
      (for-each
        (lambda (row)
          (write-source (path-expand "gerbil.pkg" (path-expand (car row) root))
            (call-with-output-string
              (lambda (out) (write (list 'package: (string->symbol (cdr row)) 'prelude: ':gerbil/core) out)))))
        (list (cons "producer" producer) (cons "consumer" consumer)))
      (write-source producer-source "(export increment) (def (increment x) (+ x 1))\n")
      (write-source consumer-source
        "(import \"../producer/value.ss\") (export answer) (def answer (increment 41))\n")
      ;; The original body retains its source location. The view changes neither
      ;; the declared compiler identity nor relative import origin. No new reader.
      (for-each
        (lambda (row)
          (def name (car row))
          (def original (cdr row))
          (write-source (path-expand (string-append name ".ss") view)
            (call-with-output-string
              (lambda (out)
                (write 'prelude: out) (display " " out) (write ':gerbil/core out) (newline out)
                (write 'package: out) (display " " out)
                (write (string->symbol (path-strip-trailing-directory-separator (path-directory name))) out)
                (newline out) (write (list 'include original) out) (newline out)))))
        (list (cons (string-append producer "/value") producer-source)
              (cons (string-append consumer "/main") consumer-source)))
      (def spec
        (list
          ;; Deliberately put the consumer first: standard imports own ordering.
          (list 'gxc: (string-append consumer "/main") (list 'extra-inputs: (list consumer-source)))
          (list 'gxc: (string-append producer "/value") (list 'extra-inputs: (list producer-source)))))
      (test root view lib bin producer consumer spec producer-source consumer-source))))
(def module-source-location-test
  (test-suite "Source-root and output-identity boundary"
    (test-case "one full-identity view compiles two packages and reuses standard products"
      (with-cross-package-view
        (lambda (_root view lib bin producer consumer spec producer-source consumer-source)
          (def original-producer (call-with-input-file producer-source read-all))
          (def original-consumer (call-with-input-file consumer-source read-all))
          ;; #f is absence; "" is truthy and changes the Gerbil's static prefix.
          (def identities (list (string-append producer "/value") (string-append consumer "/main")))
          (def cold (probe-compile-events spec view #f lib bin))
          (check-equal? (list-sort string<? cold) (list-sort string<? identities))
          (def products
            (foldr append '()
              (map (lambda (name)
                     (map (lambda (suffix) (path-expand (string-append name suffix) lib)) '(".ssi" ".o1")))
                (list (string-append producer "/value") (string-append consumer "/main")))))
          (check-equal? (andmap file-exists? products) #t)
          (def stamps (map (lambda (file) (time->seconds (file-info-last-modification-time (file-info file)))) products))
          (def prior-path (load-path))
          (dynamic-wind
            (lambda () (add-load-path! lib))
            (lambda () (check-equal? (probe-compile-events spec view #f lib bin) '()))
            (lambda () (set-load-path! prior-path)))
          (check-equal? (map (lambda (file) (time->seconds (file-info-last-modification-time (file-info file)))) products) stamps)
          (check-equal? (call-with-input-file producer-source read-all) original-producer)
          (check-equal? (call-with-input-file consumer-source read-all) original-consumer)
          (def unrelated (path-expand "unrelated/keep.txt" lib))
          (write-source unrelated "keep\n")
          (clean-probe spec view #f lib bin)
          ;; std/make clean removes its declared outputs; existing Core cleanup owns
          ;; the remaining selected .oN and named runtime output families.
          (clean-build-artifacts! (map string->symbol identities) lib)
          (check-equal? (ormap file-exists? products) #f)
          (check-equal? (file-exists? unrelated) #t)
          (displayln "SOURCE-VIEW cold=2 hot=0 upstream=unchanged selected-clean=complete unrelated=preserved"))))
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
