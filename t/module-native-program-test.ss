;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Real compiler qualification: standard exe targets retain source authority.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/ports read-all-as-u8vector)
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-checkpoint)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/module-system/building/build-projection yuanxu-project-source-spec)
        "./qualification/module-init/fixture.ss")
(export module-native-program-test)
(def (put root name text)
  (def path (path-expand name root))
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (demand root)
  (.call (prepared-package-tests root) .for-files
    (list (path-expand "probe.ss" root)) '()
    '((exe: "probe" bin: "probe-test"))))
(def module-native-program-test
  (test-suite "Init-owned standard native executable publication"
    (yuanxu-test-case "real program publication rejects stale source and altered executable"
      (call-with-temporary-directory "native-program-publication"
        (lambda (root)
          ;; This isolated temporary package is compiler Fixture data. It is
          ;; never a package boundary below the repository's test directory.
          (put root "gerbil.pkg" "(package: native-program-fixture)\n")
          (put root "init.ss"
            "(import :yuanxu/module-system/selection/init-syntax) (yuanxu! mode: explicit source: \"./modules\" (example))\n")
          (def source "(export main) (def (main . args) (displayln \"NATIVE-PROGRAM-OK\"))\n")
          (put root "probe.ss" source)
          (call-with-output-file
            (list path: (path-expand "build.ss" root) permissions: #o755)
            (lambda (out)
              (display "#!/usr/bin/env -S gerbil interactive\n" out)
              (for-each (cut pretty-print <> out)
                '((import :clan/poo/object
                    (only-in :std/source this-source-file)
                    (only-in :yuanxu/module-system/building/script defbuild-script)
                    (only-in "./init.ss" native-program-fixture.init.exports))
                  (def root (path-directory (this-source-file)))
                  (defbuild-script
                    ((.get (.call (.get native-program-fixture.init.exports tests) .for-files
                      (list (path-expand "probe.ss" root)) '()
                      '((exe: "probe" bin: "probe-test"))) std-make-spec))
                    prefix: "native-program-fixture")))))
          ;; Explicit test programs do not widen the production Module API.
          (check-exception
            (yuanxu-project-source-spec #f '((exe: "probe" bin: "probe-test"))
              root (path-expand "build.ss" root))
            (lambda (failure)
              (and (Error? failure)
                   (equal? (Error-message failure)
                     "native programs require an explicit init-owned test demand"))))
          (def pending (.get (demand root) build))
          (check-exception (.call pending .program 'native-program-fixture/probe) error?)
          (def built (build-prepared-package! root '("-:max-heap=2G,debug=q")))
          (check-equal? (.get built status) 0)
          (yuanxu-test-checkpoint 'official-program-build-completed)
          (def build (.get (demand root) build))
          (def binary (.call build .program 'native-program-fixture/probe))
          (def result (.call (.cc ProcessScript. 'command (list binary "-:max-heap=2G,debug=q") 'timeout 30) .run))
          (check-equal? (.get result status) 0)
          (check-equal? (and (string-contains (.get result output) "NATIVE-PROGRAM-OK") #t) #t)
          (check-exception (.call build .program 'native-program-fixture/other) error?)
          (def bytes (call-with-input-file binary read-all-as-u8vector))
          (dynamic-wind void
            (lambda ()
              (call-with-output-file (list path: binary truncate: #t) (cut display "tampered executable" <>))
              (check-exception (.call build .program 'native-program-fixture/probe) error?))
            (lambda ()
              (call-with-output-file (list path: binary truncate: #t)
                (lambda (out) (write-subu8vector bytes 0 (u8vector-length bytes) out)))))
          ;; Restored bytes recover only while the original source is current.
          (check-equal? (.call build .program 'native-program-fixture/probe) binary)
          (dynamic-wind void
            (lambda ()
              (put root "probe.ss" (string-append source "; changed source\n"))
              (check-exception (.call build .program 'native-program-fixture/probe) error?))
            (lambda () (put root "probe.ss" source)))
          (check-equal? (.call build .program 'native-program-fixture/probe) binary))))))
