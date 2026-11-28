;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/process run-process)
        (only-in :gerbil/expander current-expander-context make-top-context)
        (only-in :gerbil/runtime/loader load-path)
        (only-in :clan/poo/object .get .call)
        (only-in :std/make make)
        (only-in :tao3k/yuanxu/module-system/building/products current-build-output-directory)
        (only-in :tao3k/yuanxu/module-system/source/observations
                 call-with-module-source-operation-measurement)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        (only-in "./qualification/module-init/fixture.ss" import-fixture-init! with-compiler-progress))
(export module-build-cross-package-test)

(def (write-source root rel text)
  (def file (path-expand rel root))
  (create-directory* (path-directory file))
  (call-with-output-file file (lambda (port) (display text port))))

(def (file-mtime path)
  (time->seconds (file-info-last-modification-time (file-info path #t))))

(def (touch-newer! path reference-path)
  ;; Ensure the modified source timestamp is strictly greater than the compiled .ssi.
  (let loop ((attempts 0))
    (let ((src-t (file-mtime path))
          (ref-t (file-mtime reference-path)))
      (when (and (<= src-t ref-t) (< attempts 20))
        (thread-sleep! 0.05)
        (let (content (call-with-input-file path (lambda (p) (read-line p #f))))
          (call-with-output-file path (lambda (p) (display content p))))
        (loop (+ attempts 1))))))

(def (run-in-env root gerbil-dir args)
  (def status #f)
  (def host-lib (path-expand "lib" (gerbil-path)))
  (def output
    (run-process
      ["env"
       (string-append "GERBIL_PATH=" gerbil-dir)
       (string-append "GERBIL_LOADPATH=" (path-expand "lib" gerbil-dir) ":" host-lib)
       "gxi" "-:max-heap=2G,debug=q" args ...]
      directory: root stderr-redirection: #t
      check-status: (lambda (code _settings) (set! status code))))
  (values status output))

(def (setup-provider-and-consumer root)
  (def provider (path-expand "provider" root))
  (def consumer (path-expand "consumer" root))
  (def gerbil-dir (path-expand ".gerbil" consumer))
  (def pkg-parent (path-expand "pkg/github.com/example" gerbil-dir))
  (create-directory* (path-expand "lib" gerbil-dir))
  (create-directory* pkg-parent)

  ;; Upstream provider package (includes pure, FFI C-declare, unused, and broken-unused).
  (write-source provider "gerbil.pkg" "(package: example/provider)\n")
  (write-source provider "math.ss"
    "(export base-delta)\n(def (base-delta) 10)\n")
  (write-source provider "ffi-num.ss"
    "(import (only-in :std/ffi C-declare def-C-lambda))\n
     (export native-answer)\n
     (C-declare \"static int demand_fixture_answer(void) { return 42; }\")\n
     (def-C-lambda native-answer () int \"demand_fixture_answer\")\n")
  (write-source provider "api.ss"
    "(import \"./math.ss\" :example/provider/ffi-num)\n
     (export combined-answer)\n
     (def (combined-answer) (+ (base-delta) (native-answer)))\n")
  (write-source provider "unused.ss"
    "(export unused-value)\n(def unused-value 999)\n")
  (write-source provider "broken-unused.ss"
    "(this is intentionally invalid syntax ((\n")

  ;; Symlink provider into consumer's GERBIL_PATH/pkg/ like `gerbil pkg link`.
  (create-symbolic-link provider (path-expand "provider" pkg-parent))

  ;; Downstream consumer package: NO from:, NO sentinels, minimal build.ss!
  (write-source consumer "gerbil.pkg"
    "(package: example/consumer\n depend: (\"github.com/example/provider@v1.0.0\"))\n")
  (write-source consumer "init.ss"
    "(import :tao3k/yuanxu/module-system/selection/init-syntax)\n
     (yuanxu! :load-modules \"./modules\" mode: explicit :test-dir \"./t\" (app))\n")
  (write-source consumer "build.ss"
    "(import (only-in :clan/poo/object .get)\n
             (only-in :std/build-script defbuild-script)\n
             (only-in \"./init.ss\" example/consumer.init.exports))\n
     (defbuild-script (.get example/consumer.init.exports std-make-spec))\n")
  (write-source consumer "modules/app/types.ss"
    "(import :clan/poo/object (only-in :clan/poo/type Type.))\n
     (export Scope)\n
     (def Scope (.cc Type. identity: 'app-scope .element?: object?))\n")
  (write-source consumer "modules/app/objects.ss"
    "(import :clan/poo/object (only-in :example/provider/api combined-answer))\n
     (export Defaults)\n
     (def Defaults (.o answer: (combined-answer)))\n")
  (write-source consumer "modules/app/interface.ss"
    "(import (only-in :clan/poo/object .def .o) \"./types.ss\" \"./objects.ss\")\n
     (export App)\n
     (.def App identity: 'app core: (.o scope-contract: Scope exports: Defaults) features: (.o))\n")
  (values provider consumer gerbil-dir))

(def module-build-cross-package-test
  (test-suite "Cross-package on-demand dependency compilation and publication ownership"
    (test-case "cold compile builds only imported provider targets (including FFI), reuses hot, rebuilds stale"
      (call-with-temporary-directory "cross-pkg-demand"
        (lambda (root)
          (defvalues (provider consumer gerbil-dir) (setup-provider-and-consumer root))
          (def (lib-file rel) (path-expand (string-append "lib/" rel) gerbil-dir))
          (def math-ssi (lib-file "example/provider/math.ssi"))
          (def ffi-ssi (lib-file "example/provider/ffi-num.ssi"))
          (def ffi-o1 (lib-file "example/provider/ffi-num.o1"))
          (def api-ssi (lib-file "example/provider/api.ssi"))
          (def unused-ssi (lib-file "example/provider/unused.ssi"))
          (def broken-ssi (lib-file "example/provider/broken-unused.ssi"))
          (def app-ssi (lib-file "example/consumer/modules/app/interface.ssi"))

          ;; Cold state: no provider or consumer artifacts exist.
          (check-equal? (file-exists? math-ssi) #f)
          (check-equal? (file-exists? ffi-ssi) #f)
          (check-equal? (file-exists? api-ssi) #f)

          ;; 1. Cold build: ordinary `gxi build.ss compile` with ZERO from: and minimal build.ss!
          (defvalues (status1 out1) (run-in-env consumer gerbil-dir '("build.ss" "compile")))
          (unless (zero? status1) (display out1))
          (check-equal? status1 0)
          (check-equal? (file-exists? math-ssi) #t)
          (check-equal? (file-exists? ffi-ssi) #t)
          (check-equal? (file-exists? ffi-o1) #t)
          (check-equal? (file-exists? api-ssi) #t)
          (check-equal? (file-exists? app-ssi) #t)
          ;; Unused & broken upstream modules must never be compiled.
          (check-equal? (file-exists? unused-ssi) #f)
          (check-equal? (file-exists? broken-ssi) #f)

          ;; Consumer's std-make-spec must remain strictly single-package pure!
          (defvalues (spec-status spec-out) (run-in-env consumer gerbil-dir '("build.ss" "spec")))
          (unless (zero? spec-status) (display spec-out))
          (check-equal? spec-status 0)
          (check-equal? (string-contains spec-out "example/provider") #f)
          (check-equal? (number? (string-contains spec-out "modules/app/interface")) #t)

          ;; Runtime check: verify the real compiled FFI + pure answer = 52.
          (defvalues (run1-status run1-out)
            (run-in-env consumer gerbil-dir
              '("-e" "(import :clan/poo/object :example/consumer/modules/app/interface)"
                "-e" "(displayln (.get App core exports answer))")))
          (unless (zero? run1-status) (display run1-out))
          (check-equal? run1-status 0)
          (check-equal? run1-out "52\n")

          ;; 2. Hot build: already-fresh provider .ssi artifacts must be reused without recompiling.
          (def math-t1 (file-mtime math-ssi))
          (def ffi-t1 (file-mtime ffi-ssi))
          (def api-t1 (file-mtime api-ssi))
          (defvalues (status2 out2) (run-in-env consumer gerbil-dir '("build.ss" "compile")))
          (unless (zero? status2) (display out2))
          (check-equal? status2 0)
          (check-equal? (file-mtime math-ssi) math-t1)
          (check-equal? (file-mtime ffi-ssi) ffi-t1)
          (check-equal? (file-mtime api-ssi) api-t1)

          ;; 3. Stale rebuild: edit provider/math.ss -> recompiles math + api, keeps ffi-num untouched!
          (write-source provider "math.ss"
            "(export base-delta)\n(def (base-delta) 25)\n")
          (touch-newer! (path-expand "math.ss" provider) math-ssi)
          (defvalues (status3 out3) (run-in-env consumer gerbil-dir '("build.ss" "compile")))
          (unless (zero? status3) (display out3))
          (check-equal? status3 0)
          (check (> (file-mtime math-ssi) math-t1) => #t)
          (check (> (file-mtime api-ssi) api-t1) => #t)
          (check-equal? (file-mtime ffi-ssi) ffi-t1)
          (check-equal? (file-exists? unused-ssi) #f)

          ;; Runtime check: fresh process sees updated answer 25 + 42 = 67.
          (defvalues (run3-status run3-out)
            (run-in-env consumer gerbil-dir
              '("-e" "(import :clan/poo/object :example/consumer/modules/app/interface)"
                "-e" "(displayln (.get App core exports answer))")))
          (unless (zero? run3-status) (display run3-out))
          (check-equal? run3-status 0)
          (check-equal? run3-out "67\n")

          ;; 4. Clean isolation: consumer `clean` removes only consumer products, never provider .ssi!
          (defvalues (clean-status clean-out) (run-in-env consumer gerbil-dir '("build.ss" "clean")))
          (unless (zero? clean-status) (display clean-out))
          (check-equal? clean-status 0)
          (check-equal? (file-exists? app-ssi) #f)
          (check-equal? (file-exists? math-ssi) #t)
          (check-equal? (file-exists? api-ssi) #t))))

    (test-case "transitive dependency packages compile in topological package order"
      (call-with-temporary-directory "cross-pkg-chain"
        (lambda (root)
          (def base (path-expand "base" root))
          (def mid (path-expand "mid" root))
          (def consumer (path-expand "consumer" root))
          (def gerbil-dir (path-expand ".gerbil" consumer))
          (def pkg-parent (path-expand "pkg/github.com/chain" gerbil-dir))
          (create-directory* (path-expand "lib" gerbil-dir))
          (create-directory* pkg-parent)

          (write-source base "gerbil.pkg" "(package: chain/base)\n")
          (write-source base "core.ss" "(export base-v)\n(def base-v 7)\n")
          (write-source mid "gerbil.pkg"
            "(package: chain/mid\n depend: (\"github.com/chain/base\"))\n")
          (write-source mid "wrap.ss"
            "(import :chain/base/core)\n(export mid-v)\n(def mid-v (* base-v 6))\n")
          (create-symbolic-link base (path-expand "base" pkg-parent))
          (create-symbolic-link mid (path-expand "mid" pkg-parent))

          (write-source consumer "gerbil.pkg"
            "(package: chain/consumer\n depend: (\"github.com/chain/mid\"))\n")
          (write-source consumer "init.ss"
            "(import :tao3k/yuanxu/module-system/selection/init-syntax)\n
             (yuanxu! :load-modules \"./modules\" mode: explicit :test-dir \"./t\" (entry))\n")
          (write-source consumer "build.ss"
            "(import (only-in :clan/poo/object .get)\n
                     (only-in :std/build-script defbuild-script)\n
                     (only-in \"./init.ss\" chain/consumer.init.exports))\n
             (defbuild-script (.get chain/consumer.init.exports std-make-spec))\n")
          (write-source consumer "modules/entry/types.ss"
            "(import :clan/poo/object (only-in :clan/poo/type Type.))\n
             (export Scope)\n
             (def Scope (.cc Type. identity: 'entry-scope .element?: object?))\n")
          (write-source consumer "modules/entry/objects.ss"
            "(import :clan/poo/object (only-in :chain/mid/wrap mid-v))\n
             (export Defaults)\n
             (def Defaults (.o value: mid-v))\n")
          (write-source consumer "modules/entry/interface.ss"
            "(import (only-in :clan/poo/object .def .o) \"./types.ss\" \"./objects.ss\")\n
             (export Entry)\n
             (.def Entry identity: 'entry core: (.o scope-contract: Scope exports: Defaults) features: (.o))\n")

          (defvalues (status out) (run-in-env consumer gerbil-dir '("build.ss" "compile")))
          (unless (zero? status) (display out))
          (check-equal? status 0)
          (check-equal? (file-exists? (path-expand "lib/chain/base/core.ssi" gerbil-dir)) #t)
          (check-equal? (file-exists? (path-expand "lib/chain/mid/wrap.ssi" gerbil-dir)) #t)
          (check-equal? (file-exists? (path-expand "lib/chain/consumer/modules/entry/interface.ssi" gerbil-dir)) #t)
          (defvalues (run-status run-out)
            (run-in-env consumer gerbil-dir
              '("-e" "(import :clan/poo/object :chain/consumer/modules/entry/interface)"
                "-e" "(displayln (.get Entry core exports value))")))
          (unless (zero? run-status) (display run-out))
          (check-equal? run-status 0)
          (check-equal? run-out "42\n"))))

    (yuanxu-test-case "selected module importing another selected module interface reconciles publication and source"
      (for-each
        (lambda (order)
          (call-with-temporary-directory "pub-vs-source"
            (lambda (root)
              (def package (symbol->string (gensym 'pub-src-)))
              (def init (path-expand "init.ss" root))
              (def lib (path-expand "lib" root))
              (create-directory* lib)
              (write-source root "gerbil.pkg" (string-append "(package: " package ")\n"))
              (write-source root "init.ss"
                (string-append
                  "(import :tao3k/yuanxu/module-system/selection/init-syntax)\n"
                  "(yuanxu! :load-modules \"./modules\" mode: explicit :test-dir \"./t\" "
                  order ")\n"))
              (write-source root "modules/alpha/types.ss"
                "(import :clan/poo/object (only-in :clan/poo/type Type.))\n
                 (export Scope)\n
                 (def Scope (.cc Type. identity: 'alpha-scope .element?: object?))\n")
              (write-source root "modules/alpha/objects.ss"
                "(import :clan/poo/object)\n(export Defaults)\n(def Defaults (.o label: 'alpha-ok))\n")
              (write-source root "modules/alpha/interface.ss"
                "(import (only-in :clan/poo/object .def .o) \"./types.ss\" \"./objects.ss\")\n
                 (export Alpha)\n
                 (.def Alpha identity: 'alpha core: (.o scope-contract: Scope exports: Defaults) features: (.o))\n")
              (write-source root "modules/beta/types.ss"
                "(import :clan/poo/object (only-in :clan/poo/type Type.))\n
                 (export Scope)\n
                 (def Scope (.cc Type. identity: 'beta-scope .element?: object?))\n")
              (write-source root "modules/beta/helper.ss"
                "(import (only-in :clan/poo/object .get) \"../alpha/interface.ss\")\n
                 (export alpha-label)\n
                 (def (alpha-label) (.get Alpha core exports label))\n")
              (write-source root "modules/beta/objects.ss"
                "(import :clan/poo/object \"./helper.ss\")\n
                 (export Defaults)\n
                 (def Defaults (.o from-alpha: (alpha-label)))\n")
              (write-source root "modules/beta/interface.ss"
                "(import (only-in :clan/poo/object .def .o) \"./types.ss\" \"./objects.ss\")\n
                 (export Beta)\n
                 (.def Beta identity: 'beta core: (.o scope-contract: Scope exports: Defaults) features: (.o))\n")
              (parameterize ((current-expander-context (make-top-context))
                             (current-build-output-directory lib))
                (def exports (import-fixture-init! init))
                (def input-path (load-path))
                (defvalues (spec work)
                  (call-with-module-source-operation-measurement
                    (lambda () (.get exports std-make-spec))
                    accounting?: #f))
                (check-equal? (hash-ref work '(calls scope-factory) 0) 0)
                (check-equal? (load-path) input-path)
                (check (pair? spec) => #t)
                (with-compiler-progress
                  (lambda ()
                    (.call exports .compile-selection '(alpha beta) '()
                      (lambda (targets source-root)
                        (make targets srcdir: source-root libdir: lib)))))
                (check-equal? (load-path) input-path)
                (check-equal? (file-exists? (path-expand (string-append package "/modules/alpha/interface.ssi") lib)) #t)
                (check-equal? (file-exists? (path-expand (string-append package "/modules/beta/interface.ssi") lib)) #t)))))
        '("(alpha) (beta)" "(beta) (alpha)")))))
