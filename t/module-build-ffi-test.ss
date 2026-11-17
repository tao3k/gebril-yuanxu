;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/process run-process))
(export module-build-ffi-test)

(def (write-source root name text)
  (def file (path-expand name root))
  (create-directory* (path-directory file))
  (call-with-output-file file (cut display text <>)))

(def (fixture root build)
  (create-directory* (path-expand ".gerbil/lib" root))
  (write-source root "gerbil.pkg" "(package: ffi-build-fixture prelude: :tao3k/yuanxu/prelude)\n")
  (write-source root "init.ss"
    "(import :tao3k/yuanxu/module-system/selection/init-syntax)
     (yuanxu! :load-modules \"./modules\" mode: explicit :test-dir \"./t\" (consumer) (clock))")
  (write-source root "build.ss"
    "(import (only-in :clan/poo/object .get .o)
             (only-in :std/source this-source-file)
             (only-in :std/build-script defbuild-script)
             (only-in :tao3k/yuanxu/module-system/building/build-script defmodule-build-script)
             (only-in \"./init.ss\" ffi-build-fixture.init.exports))
     (defmodule-build-script
       (defbuild-script (.get ffi-build-fixture.init.exports std-make-spec))
       (.o))")
  (for-each
    (lambda (name)
      (def directory (path-expand name (path-expand "modules" root)))
      (write-source directory "types.ss"
        "(import (only-in :clan/poo/type Type.))
         (export Scope)
         (def Scope (.cc Type. identity: 'clock-scope .element?: object?))")
      (write-source directory "objects.ss" "(export Defaults) (def Defaults (.o))")
      (write-source directory "config.ss" "(def Config (.o))"))
    '("consumer" "clock"))
  (write-source root "modules/consumer/interface.ss"
    "(import \"types.ss\" \"value.ss\")
     (.def Consumer identity: 'consumer
       core: (.o scope-contract: Scope exports: (.o value: reading))
       features: (.o))")
  (write-source root "modules/consumer/value.ss"
    "(import \"../clock/clock.ss\")
     (export reading)
     (def reading (clock-value))")
  (write-source root "modules/clock/interface.ss"
    "(import \"types.ss\" \"clock.ss\")
     (.def Clock identity: 'clock
       core: (.o scope-contract: Scope
                 exports: (let (reading (clock-value)) (.o value: reading)))
       features: (.o))")
  (write-source root "modules/clock/clock.ss"
    "(import (only-in :std/ffi C-declare def-C-lambda))
     (export clock-value)
     (C-declare \"static int clock_fixture_value(void) { return 42; }\")
     (def-C-lambda clock-value () int \"clock_fixture_value\")")
  (write-source root "modules/clock/build.ss" build))

(def (run-fixture root args)
  (def status #f)
  (def output
    (run-process
      ["env" (string-append "GERBIL_PATH=" (path-expand ".gerbil" root))
             (string-append "GERBIL_LOADPATH=" (path-expand "lib" (gerbil-path)))
             "gxi" "-:max-heap=2G,debug=q" args ...]
      directory: root stderr-redirection: #t
      check-status: (lambda (code _settings) (set! status code))))
  (values status output))

(def module-build-ffi-test
  (test-suite "Module FFI Build admission"
    (test-case "cold native Make builds a selected dependency before evaluating the Interface"
      (call-with-temporary-directory "module-ffi"
        (lambda (root)
          (fixture root "(.def Build ffi: '(\"clock\") defbuild-script: (.o spec: '()))")
          (def artifact (path-expand ".gerbil/lib/ffi-build-fixture/modules/clock/clock.o1" root))
          (check-equal? (file-exists? artifact) #f)
          (defvalues (status output) (run-fixture root '("build.ss" "compile")))
          (unless (zero? status) (display output))
          (check-equal? status 0)
          (check-equal? (file-exists? artifact) #t)
          (defvalues (loaded result)
            (run-fixture root
              '("-e" "(import :ffi-build-fixture/modules/clock/clock)"
                "-e" "(displayln (clock-value))")))
          (unless (zero? loaded) (display result))
          (check-equal? loaded 0)
          (check-equal? result "42\n"))))
    (test-case "a cold undeclared FFI target cannot be imported during projection"
      (call-with-temporary-directory "undeclared-module-ffi"
        (lambda (root)
          (fixture root "(.def Build defbuild-script: (.o spec: '()))")
          (defvalues (status output) (run-fixture root '("build.ss" "compile")))
          (check-equal? (zero? status) #f)
          (unless (string-contains output "##c-declare") (display output))
          (check-equal? (number? (string-contains output "##c-declare")) #t)
          (check-equal?
            (file-exists? (path-expand ".gerbil/lib/ffi-build-fixture/modules/clock/clock.o1" root))
            #f))))))
