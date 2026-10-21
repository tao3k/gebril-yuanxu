;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/loader/objects)

(export module-loader-backend-test)

(def module-loader-backend-test
  (test-suite "Core Module Loader Backend"
    (yuanxu-test-case "lazy values do not invoke their backend before force"
      (let* ((calls 0)
             (source (make-yuanxu-module-local-source "feature/interface.ss"))
             (module (.o name: 'feature))
             (backend
              (make-yuanxu-module-loader-backend
               'static 'local
               (lambda (requested)
                 (set! calls (+ calls 1))
                 (if (yuanxu-module-source-ref=? requested source)
                   module
                   #f))
               '()))
             (deferred (yuanxu-make-lazy-load-plan (list backend) source)))
        (check-equal? calls 0)
        (check-equal? (yuanxu-lazy-load-plan-forced? deferred) #f)
        (check-equal? (yuanxu-module-load-receipt-code
                       (yuanxu-lazy-load-plan-receipt deferred))
                      'deferred)
        (let* ((forced (yuanxu-force-lazy-load-plan deferred))
               (receipt (yuanxu-lazy-load-plan-receipt forced)))
          (check-equal? calls 1)
          (check-equal? (yuanxu-lazy-load-plan-forced? forced) #t)
          (check-equal? (yuanxu-module-load-receipt-loaded? receipt) #t)
          (check-equal? (yuanxu-module-load-receipt->alist receipt)
                        '((source (kind . local)
                                  (value . "feature/interface.ss")
                                  (metadata))
                          (module . feature)
                          (backend-name . static)
                          (loaded? . #t)
                          (code . loaded)
                          (messages)
                          (metadata))))))
    (yuanxu-test-case "unsupported sources remain missing receipts"
      (let* ((source (make-yuanxu-module-package-source 'other))
             (backend (yuanxu-module-static-loader 'local 'local '()))
             (receipt (yuanxu-module-load-source-receipt
                       (list backend) source)))
        (check-equal? (yuanxu-module-load-receipt-loaded? receipt) #f)
        (check-equal? (yuanxu-module-load-receipt-code receipt)
                      'missing-loader)))))
