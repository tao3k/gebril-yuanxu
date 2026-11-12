;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-source selection is inert and retains its own source admission.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-module-import)
        (only-in :tao3k/yuanxu/module-system/building/test-projection
                 module-test-file-source))
(export module-test-executor-import-test)

(def (put path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))

(def module-test-executor-import-test
  (test-suite "Inert test source import ownership"
    (test-case "metadata never imports an executor or waives source admission"
      (call-with-temporary-directory "runtime-test-factory-"
        (lambda (directory)
          (def file (path-expand "probe-test.ss" directory))
          (put file "(import :std/test) (export probe-test) (def probe-test (test-suite \"probe\" (test-case \"runtime\" (check-equal? 42 42))))")
          (def source (module-test-file-source (list file)))
          (def imports 0)
          (def (publication-import path reload?)
            (set! imports (+ imports 1))
            (error "selected publication must not load runtime executor" path))
          (def selected
            (parameterize ((current-expander-module-import publication-import))
              (def result (module-test-file-source (list file)))
              ((.get result admit-current))
              (check-equal? (eq? (current-expander-module-import) publication-import) #t)
              result))
          (check-equal? imports 0)
          (check-equal? (.get selected spec) (list file))
          (for-each (lambda (name) (check-equal? (.slot? selected name) #f))
                    '(.run .compile execution))
          ;; Source admission belongs to the metadata itself, not a launcher.
          (put file "(import :std/test) (export changed)")
          (check-exception ((.get selected admit-current)) error?))))))
