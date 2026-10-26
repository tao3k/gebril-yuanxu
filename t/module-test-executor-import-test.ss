;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native factory loading is separate from selected-suite source admission.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-module-import)
        (only-in :yuanxu/module-system/building/test-projection
                 module-test-file-source module-test-execution))
(export module-test-executor-import-test)

(def (put path text)
  (call-with-output-file (list path: path truncate: #t)
    (lambda (port) (display text port))))

(def module-test-executor-import-test
  (test-suite "Lazy native executor import ownership"
    (test-case "publication importer cannot capture the factory or waive source admission"
      (call-with-temporary-directory "native-test-factory-"
        (lambda (directory)
          (def file (path-expand "probe-test.ss" directory))
          (put file "(import :std/test) (export probe-test) (def probe-test (test-suite \"probe\" (test-case \"native\" (check-equal? 42 42))))")
          (def source (module-test-file-source (list file)))
          (def imports 0)
          (def (publication-import path reload?)
            (set! imports (+ imports 1))
            (error "selected publication must not load native executor" path))
          (def execution
            (parameterize ((current-expander-module-import publication-import))
              (def result (module-test-execution source))
              (check-equal? (eq? (current-expander-module-import) publication-import) #t)
              result))
          (check-equal? imports 0)
          (check-equal? (.get (.call execution .run) status) 0)
          ;; Native factory ownership never authenticates changed suite bytes.
          ;; Keep the replacement valid and observe the command boundary, so a
          ;; parser/command failure cannot masquerade as source refusal.
          (def started? #f)
          (.def (Changed @ execution)
            command: (begin (set! started? #t) '("false")))
          (put file "(import :std/test) (export probe-test) (def probe-test (test-suite \"changed\" (test-case \"native\" (check-equal? 43 43))))")
          (check-exception (.call Changed .run) error?)
          (check-equal? started? #f))))))
