;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Embedded programs use __compile-top; gxi normally adds an outer source pair.
(import :std/test
        (only-in :gerbil/runtime __compile-top __compile-top-source __scheme-source)
        (only-in :gerbil/expander current-expander-compile current-expander-eval)
        (only-in :clan/poo/object .get .call)
        (only-in :tao3k/yuanxu/module-system/source/reader module-publication-reader)
        (only-in "qualification/module-publication/fixtures.ss" write-file with-publication-source))
(export module-publication-compiler-test)

(def module-publication-compiler-test
  (test-suite "Publication delivery preserves both native compiler carriers"
    (test-case "embedded compiler delivers a closed private declaration"
      (with-publication-source
        (lambda (_root module-root source _view)
          (write-file (path-expand "interface.ss" module-root)
            "(.def Fixture identity: 'custom/example
               core: (.o scope-contract: FixtureContract exports: (.o value: 42))
               features: (.o))")
          (parameterize ((current-expander-compile __compile-top)
                         (current-expander-eval ##eval)
                         (__scheme-source 'embedded-test))
            (def reader (module-publication-reader))
            (check-equal? (.get (.call reader read source) core exports value) 42)
            ((.get reader admit-current))))))
    (test-case "gxi compiler delivers the same closed private declaration"
      (with-publication-source
        (lambda (_root module-root source _view)
          (write-file (path-expand "interface.ss" module-root)
            "(.def Fixture identity: 'custom/example
               core: (.o scope-contract: FixtureContract exports: (.o value: 42))
               features: (.o))")
          (parameterize ((current-expander-compile __compile-top-source))
            (def reader (module-publication-reader))
            (check-equal? (.get (.call reader read source) core exports value) 42)
            ((.get reader admit-current))))))))
