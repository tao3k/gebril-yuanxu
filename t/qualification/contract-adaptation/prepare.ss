;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; SDK-only preparation: discussion code becomes private temporary test modules.
(import :gerbil/core)
(export prepare-contract-fixture copy-contract-test-sources)

(def (scheme-blocks path)
  (call-with-input-file path
    (lambda (port)
      (let loop ((inside? #f) (lines '()) (blocks '()))
        (let (line (read-line port))
          (cond
            ((eof-object? line) (reverse blocks))
            ((equal? line "#+begin_src scheme") (loop #t '() blocks))
            ((and inside? (equal? line "#+end_src"))
             (loop #f '() (cons (apply string-append (reverse lines)) blocks)))
            (inside? (loop #t (cons (string-append line "\n") lines) blocks))
            (else (loop #f lines blocks))))))))

(def (write-source path text)
  (call-with-output-file path (lambda (port) (display text port))))

(def (copy-contract-test-sources source-directory destination)
  (for-each
    (lambda (name)
      (call-with-input-file (path-expand name source-directory)
        (lambda (port)
          (write-source (path-expand name destination)
            (let loop ((lines '()))
              (let (line (read-line port))
                (if (eof-object? line)
                  (apply string-append (reverse lines))
                  (loop (cons (string-append line "\n") lines)))))))))
    '("generic-test.ss" "schema-test.ss" "receipt-fixture.ss"
      "evidence-binding-test.ss")))

(def (prepare-contract-fixture document destination)
  (let (blocks (scheme-blocks document))
    (unless (= (length blocks) 7)
      (error "Design block layout changed: review fixture extraction"))
    (write-source (path-expand "fixture-schema.ss" destination)
      (string-append
        "(import :clan/poo/object :clan/poo/mop :clan/poo/type\n"
        " (only-in :std/list/list foldl) :clan/poo/object-contract\n"
        " :yuanxu/modules/json-schema/contracts)\n(export #t)\n"
        (list-ref blocks 3)))
    (write-source (path-expand "fixture-core.ss" destination)
      (string-append
        "(import :clan/poo/object (only-in :gerbil/core/contract using) :clan/poo/object-contract\n"
        " (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence\n"
        "  yuanxu-contract-admit yuanxu-validation-evidence-accepted?))\n(export #t)\n"
        (list-ref blocks 5)))))
