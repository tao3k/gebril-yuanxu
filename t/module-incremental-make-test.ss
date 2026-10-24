;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The installed std/make owns all decisions; this test only observes its log
;;; and real .ssi/.o1 outputs. No compiler, cache protocol or Builder substitute.
(import :std/test :clan/poo/object
        (only-in :std/make make)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture))
(export module-incremental-make-test)
(def (write-source root name content)
  (call-with-output-file (list path: (path-expand name root) truncate: #t)
    (cut display content <>)))
(def (compile-lines output)
  (call-with-input-string output
    (lambda (port)
      (let next ((lines '()))
        (def line (read-line port))
        (cond ((eof-object? line) (reverse lines))
              ((string-prefix? "... compile " line)
               (next (cons (substring line 12 (string-length line)) lines)))
              (else (next lines)))))))
(def (native-make root lib)
  (def output (open-output-string))
  (parameterize ((current-output-port output))
    (make '("provider" "consumer" "unrelated")
      srcdir: root libdir: lib bindir: (path-expand "bin" root)
      parallelize: #f optimize: #f))
  (compile-lines (get-output-string output)))
(def module-incremental-make-test
  (test-suite "Installed std/make incremental source closure"
    (yuanxu-test-fixture "one source edit rebuilds its importer, not an unrelated module"
      (fixture (.cc DirectoryFixture prefix: "incremental-make-"))
      (def root (.get fixture root))
      (def lib (path-expand "lib" root))
      (def package (symbol->string (gensym 'incremental-)))
      (write-source root "gerbil.pkg" (string-append "(package: " package ")\n"))
      (write-source root "provider.ss" "(export value)\n(def value 1)\n")
      (write-source root "consumer.ss" "(import \"./provider\")\n(export answer)\n(def answer (+ value 1))\n")
      (write-source root "unrelated.ss" "(export constant)\n(def constant 'unchanged)\n")
      (def prior-path (load-path))
      (dynamic-wind
        (lambda () (add-load-path! lib))
        (lambda ()
          (def cold (native-make root lib))
          (check-equal? (length cold) 3)
          (for-each
            (lambda (name)
              (check-equal? (and (member name cold) #t) #t)
              (for-each
                (lambda (suffix)
                  (check-equal? (file-exists? (path-expand
                    (string-append package "/" name suffix) lib)) #t)) '(".ssi" "~0.o1")))
            '("provider" "consumer" "unrelated"))
          (check-equal? (native-make root lib) '())
          (def unrelated (path-expand (string-append package "/unrelated.ssi") lib))
          (def unchanged-time (file-info-last-modification-time (file-info unrelated)))
          ;; std/make uses modification times, not content hashes. Cross a
          ;; filesystem timestamp tick; this is not a relaxed watchdog.
          (thread-sleep! 1.1)
          (write-source root "provider.ss" "(export value)\n(def value 2)\n")
          (def edited (native-make root lib))
          (check-equal? edited '("provider" "consumer"))
          (check-equal? (time->seconds (file-info-last-modification-time (file-info unrelated)))
                        (time->seconds unchanged-time))
          (check-equal? (native-make root lib) '())
          (displayln "INCREMENTAL-MAKE cold=3 hot=0 source-edit=2 unrelated=unchanged next-hot=0"))
        (lambda () (set-load-path! prior-path))))))
