;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :std/misc/process run-process)
        (only-in :gerbil/expander current-expander-module-import)
        (only-in :clan/poo/object .def .call .get .o)
        (only-in :clan/poo/type False Fun String TypeError?)
        (only-in :clan/poo/number Integer)
        (only-in :tao3k/yuanxu/prelude yuanxu-module-declaration yuanxu-autoload)
        (only-in :tao3k/yuanxu/ops/objects ProcessScript.)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :tao3k/yuanxu/observability/testing-fixture with-yuanxu-fixture)
        (only-in "./qualification/testing/directory.ss" DirectoryFixture write-source))
(export module-autoload-declaration-test)

(def module-autoload-declaration-test
  (test-suite "Compiled module declarations"
    (yuanxu-test-case "Gerbil initializes the declaring module once without expansion"
      (with-yuanxu-fixture (fixture DirectoryFixture)
        (def root (.get fixture root))
        (def state (path-expand ".gerbil" root))
        (def receipt (path-expand "initialized" root))
        (def caller (current-directory))
        (def inherited (load-path))
        (write-source (path-expand "gerbil.pkg" root)
          "(package: yuanxu-autoload-declaration-test)\n")
        (def build-script (path-expand "build.ss" root))
        (write-source build-script
          "#!/usr/bin/env gxi\n(import (only-in :std/build-script defbuild-script))\n(defbuild-script '(\"payload\"))\n")
        (run-process (list "chmod" "+x" build-script))
        (write-source (path-expand "payload.ss" root)
          (string-append
            "(import (only-in :tao3k/yuanxu/prelude define-yuanxu-module-declaration))\n"
            "(export datum increment)\n"
            "(call-with-output-file (list path: \"initialized\" append: #t) "
            "  (lambda (port) (display \"once\" port)))\n"
            "(define-yuanxu-module-declaration datum #f)\n"
            "(define-yuanxu-module-declaration increment (lambda (value) (+ value 1)))\n"))
        (.def (Build @ ProcessScript.)
          command: '("gerbil" "build")
          directory: root
          environment: (.o GERBIL_PATH: state GERBIL_LOADPATH: (string-join inherited ":"))
          timeout: 60
          check-status: #f)
        (def built (.call Build .run))
        (unless (zero? (.get built status))
          (error "declaration fixture did not build" (.get built output)))
        (def owner ':yuanxu-autoload-declaration-test/payload)
        (def invoke
          (parameterize ((current-directory root))
            (yuanxu-autoload owner 'increment contract: (Fun Integer <- Integer))))
        (check-equal? (file-exists? receipt) #f)
        (dynamic-wind
          (lambda () (add-load-path! (path-expand "lib" state)))
          (lambda ()
            (parameterize ((current-expander-module-import
                             (lambda _ (error "declaration entered the expander"))))
              (check-equal? (yuanxu-module-declaration owner 'datum False directory: root) #f)
              (check-equal? (invoke 41) 42)
              (check-equal? (invoke 42) 43)
              (check-equal? (call-with-input-file receipt read-line) "once")
              (check-equal?
                (with-catch TypeError?
                  (lambda () (yuanxu-module-declaration owner 'datum String directory: root) #f)) #t)
              (check-equal?
                (with-catch TypeError?
                  (lambda () (yuanxu-module-declaration ':../payload 'datum False directory: root) #f)) #t)
              (check-equal?
                (with-catch (lambda (_) #t)
                  (lambda () (yuanxu-module-declaration owner 'missing False directory: root) #f)) #t)
              (check-equal? (current-directory) caller)))
          (lambda () (set-load-path! inherited)))))))
