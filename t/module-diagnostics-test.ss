;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object object?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/observability/diagnostics)

(export module-diagnostics-test)

(def module-diagnostics-test
  (test-suite "Core Module diagnostic values"
    (yuanxu-test-case "POO values preserve facts without product coupling"
      (let* ((diagnostic
              (make-yuanxu-module-diagnostic
               'warning 'duplicate 'module '((name . example))))
             (report
              (make-yuanxu-module-doctor-report
               '(example) 'warning (list diagnostic))))
        (check-equal? (object? diagnostic) #t)
        (check-equal? (yuanxu-module-diagnostic? diagnostic) #t)
        (check-equal? (yuanxu-module-diagnostic-code diagnostic) 'duplicate)
        (check-equal? (yuanxu-module-doctor-report? report) #t)
        (check-equal? (yuanxu-module-doctor-report-modules report)
                      '(example))
        (check-equal? (yuanxu-module-doctor-ok? report) #f)))
    (yuanxu-test-case "status scans warnings and detects a late error"
      (let* ((warnings
              (map (lambda (index)
                     (make-yuanxu-module-diagnostic
                      'warning 'notice index '()))
                   (iota 1000)))
             (error-fact
              (make-yuanxu-module-diagnostic
               'error 'invalid 'module '())))
        (check-equal? (yuanxu-module-diagnostics-status '()) 'ok)
        (check-equal? (yuanxu-module-diagnostics-status warnings) 'warning)
        (check-equal? (yuanxu-module-diagnostics-status
                       (append warnings (list error-fact)))
                      'error)))))
