;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/funs)

(export module-context-test)

(def module-context-test
  (test-suite "Core Module context queries"
    (yuanxu-test-case "phase and hook queries read metadata only"
      (let (module
            (.o phase-files: '((config . "config.ss"))
                hooks: '((after-config . one))))
        (check-equal? (yuanxu-module-phase-file module 'config) "config.ss")
        (check-equal? (yuanxu-module-phase-file module 'init 'absent) 'absent)
        (check-equal? (yuanxu-module-hook-values module 'after-config)
                      '(one))))
    (yuanxu-test-case "positive and negative flags are pure predicates"
      (let (module (.o flags: '(+fast +safe)))
        (check-equal? (yuanxu-module-flag-enabled? module '+fast) #t)
        (check-equal? (yuanxu-module-flags-enabled?
                       module '(+fast -missing))
                      #t)
        (check-equal? (yuanxu-module-flag-enabled? module '-safe) #f)))
    (yuanxu-test-case "depth order is stable for equal values"
      (let* ((late (.o name: 'late depth: (cons 10 20)))
             (first (.o name: 'first depth: (cons -10 0)))
             (second (.o name: 'second depth: (cons 0 0))))
        (check-equal? (yuanxu-module-depth-value late 'init) 10)
        (check-equal?
         (yuanxu-module-phase-order (list late first second) 'config)
         (list first second late))))))
