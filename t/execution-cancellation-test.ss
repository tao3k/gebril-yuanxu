;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :std/os/pid getpid)
        (only-in :std/os/signal kill SIGTERM)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture with-yuanxu-fixture))
(export execution-cancellation-test)

(def execution-cancellation-test
  (test-suite "Outer termination unwinds the fixture and owned Ops effect"
    (yuanxu-test-case "TERM reaches the owner once and releases nested fixtures"
      (def root (make-temporary-file-name "fixture-term-"))
      (def releases '())
      (.def Directory
        .acquire: (lambda () (create-directory root) root)
        .release: (lambda (resource)
                    (set! releases (cons 'directory releases))
                    (clear-temporary-file! resource)))
      (.def Inner
        .acquire: (lambda () 'inner)
        .release: (lambda (_resource) (set! releases (cons 'inner releases))))
      (def sender #f)
      (def failure
        (with-catch values
          (lambda ()
            (with-yuanxu-fixture (directory Directory)
              (with-yuanxu-fixture (_inner Inner)
                ;; Real OS TERM, sent only after fixture acquisition and while
                ;; the same owner is blocked in the existing Ops .run path.
                (set! sender
                  (thread-start!
                    (make-thread (lambda () (thread-sleep! 0.2)
                                   (kill (getpid) SIGTERM)))))
                (.def (Wait @ ProcessScript.) command: '("sleep" "30") timeout: 30)
                (.call Wait .run))))))
      (when sender (thread-join! sender))
      (check-equal? (and (Error? failure) (Error-message failure))
                    "Ops execution terminated")
      (check-equal? releases '(directory inner))
      (check-equal? (file-exists? root) #f)
      ;; A subsequent fixture registers afresh: cancellation is no stored
      ;; approval, persistent resource registry or poisoned execution result.
      (with-yuanxu-fixture (_directory Directory) (check-equal? (file-exists? root) #t))
      (check-equal? releases '(directory directory inner))
      (check-equal? (file-exists? root) #f))))
