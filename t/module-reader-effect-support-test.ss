;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; An import closure describes code use, not all effects of native Scheme.
(import :std/test :clan/poo/object
        (only-in "./qualification/module-publication/fixtures.ss" with-publication-source write-file)
        (only-in :yuanxu/module-system/source/reader module-publication-reader)
        (only-in :yuanxu/module-system/source/admission module-source-read)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export module-reader-effect-support-test)
(def module-reader-effect-support-test
  (test-suite "Reader import support versus ambient effects"
    (yuanxu-test-case "entry and return retain ambient source obligations"
      (for-each
        (lambda (phase)
          (with-publication-source
            (lambda (root first-root _source _view)
              (def second-root (path-expand "modules/custom/other" root))
              (def first-config (path-expand "config.ss" first-root))
              (def marker (path-expand "second-initialized" root))
              (def replacement "(def Greeting \"changed\") (export Greeting)")
              (for-each
                (lambda (role)
                  (write-file (path-expand role second-root)
                    (module-source-read (path-expand role first-root))))
                '("types.ss" "objects.ss"))
              ;; There is deliberately NO import of the first Module. A native
              ;; initializer can still change its source through ordinary IO.
              (write-file (path-expand "config.ss" second-root)
                (string-append
                  (if (eq? phase 'return)
                    (string-append "(call-with-output-file (list path: "
                      (object->string first-config) " truncate: #t) (lambda (p) (display "
                      (object->string replacement) " p))) ") "")
                  "(call-with-output-file " (object->string marker)
                  " (lambda (p) (display \"initialized\" p))) "
                  "(def Greeting \"other\") (export Greeting)"))
              (write-file (path-expand "interface.ss" second-root)
                "(.def Module identity: 'custom/other core: (.o requires: (.o) scope-contract: FixtureContract exports: (.o greeting: Greeting)) features: (.o))")
              (def view (yuanxu-load-modules (path-expand "modules" root)))
              (def locate (.get view context locate))
              (def reader (module-publication-reader))
              (.call reader read (locate 'custom/example))
              (when (eq? phase 'entry) (write-file first-config replacement))
              (check-exception
                (call-with-values
                  (lambda () (.call reader read-located (lambda () (locate 'custom/other))))
                  (lambda (_source _value) 'unexpected-success)) error?)
              ;; Entry refusal is before the initializer; return refusal is
              ;; after its real effect. Neither publishes a successful value.
              (check-equal? (file-exists? marker) (eq? phase 'return))
              (check-exception (.call reader admit-current) error?))))
        '(entry return)))))
