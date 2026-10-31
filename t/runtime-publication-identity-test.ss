;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Runtime selection must not reinstall canonical library definitions.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop validate)
        (only-in :std/source this-source-file)
        (only-in :gerbil/expander eval-syntax make-top-context current-expander-context)
        (only-in :yuanxu/observability/types YuanxuDebugDurationReceiptContract))
(export runtime-publication-identity-test)
(def root (path-expand ".." (path-directory (this-source-file))))
(def runtime-publication-identity-test
  (test-suite "Runtime publication preserves installed contract identity"
    (test-case "source init build projection preserves held watchdog receipts"
      (def contract YuanxuDebugDurationReceiptContract)
      (def proto (.ref contract 'proto))
      (def held (.o (:: @ proto)
                   phase: 'identity-probe policy-label: 'testing/default-case
                   limit-milliseconds: 100 elapsed-milliseconds: 101
                   accepted?: #f reason: 'idle-exceeded))
      (check-equal? (eq? (validate contract held) held) #t)
      (def paths (load-path))
      (parameterize ((current-expander-context (make-top-context)))
        (eval-syntax '(import :gerbil/core))
    (eval-syntax '(import (only-in :clan/poo/object .get)))
        (eval-syntax `(import (only-in ,(path-expand "init.ss" root) yuanxu.init.exports)))
        (check-equal? (load-path) paths)
        (check-equal? (pair? ((eval-syntax '(.get yuanxu.init.exports std-make-spec)) '())) #t))
      ;; Projection returns build data; only the actual build entry may
      ;; prioritize source packages in its own compiler process.
      (check-equal? (load-path) paths)
      (check-equal? (eq? contract YuanxuDebugDurationReceiptContract) #t)
      (check-equal? (eq? proto (.ref YuanxuDebugDurationReceiptContract 'proto)) #t)
      (check-equal? (eq? (validate YuanxuDebugDurationReceiptContract held) held) #t))))
