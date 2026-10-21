;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .o .ref .call)
        (only-in :clan/poo/mop define-type element?)
        (only-in :yuanxu/types
                 YuanxuObjectContract.
                 yuanxu-predicate-contract
                 yuanxu-contract-admit
                 yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/object-family/syntax
                 defpoo-object-family)
        (only-in :yuanxu/composition/lineage
                 yuanxu-lineage-analysis
                 yuanxu-lineage-cycle?
                 yuanxu-productive-recursion?)
        (only-in :yuanxu/observability/debug
                 YuanxuDebugMemoryAnomaly?
                 yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/observability/testing-case
                 yuanxu-default-testing-case-profile
                 yuanxu-testing-case-profile?
                 yuanxu-test-case/with))
(export core-test)

(define-type (CoreNameContract @ YuanxuObjectContract.)
  identity: 'core/name
  proto: (.o)
  responsibilities: (.o name: (yuanxu-predicate-contract
                              'core/name-symbol symbol?
                              (lambda (_candidate _context) '()))))

(defpoo-object-family
  (accessors (core-name name))
  (projections (core->alist (name name))))

(def +core-case-profile+
  (.o (:: @ yuanxu-default-testing-case-profile)
      (identity 'core/qualification)
      (max-duration-milliseconds 2000)))

(def core-test
  (test-suite "Core"
    (test-case "native contracts retain prototype ancestry"
      (let* ((proto (.ref CoreNameContract 'proto))
             (value (.o (:: @ proto) name: 'core)))
        (check-equal? (element? CoreNameContract value) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit CoreNameContract value #f))
                      #t)
        (check-equal? (element? CoreNameContract (.o name: 'core)) #f)))
    (test-case "object-family projection stays POO-native"
      (let (value (.o name: 'core))
        (check-equal? (core-name value) 'core)
        (check-equal? (core->alist value) '((name . core)))))
    (test-case "lineage distinguishes cycles and productive recursion"
      (check-equal? (yuanxu-lineage-cycle? '(a b c)) #f)
      (check-equal? (yuanxu-lineage-cycle? '(a b a)) #t)
      (check-equal? (yuanxu-productive-recursion? '(a b a) '(b)) #t)
      (check-equal? (yuanxu-productive-recursion? '(a b a) '(c)) #f)
      (check-equal? (.ref (yuanxu-lineage-analysis '(a b c) '(b)) 'status)
                    'acyclic)
      (check-equal? (.ref (yuanxu-lineage-analysis '(a b a) '(b)) 'status)
                    'productive-recursion)
      (check-equal? (.ref (yuanxu-lineage-analysis '(a b a) '(c)) 'status)
                    'non-productive-cycle))
    (test-case "Core samples Gambit memory without ASP"
      (let (sample (yuanxu-debug-memory-snapshot 'core/qualification))
        (check-equal? (.ref sample 'phase) 'core/qualification)
        (check-equal? (exact-integer? (.ref sample 'heap-size-bytes)) #t)))
    (yuanxu-test-case/with +core-case-profile+
      "Case profile extends Core memory and duration slots"
      (check-equal? (yuanxu-testing-case-profile?
                     +core-case-profile+) #t)
      (check-equal? (.ref +core-case-profile+ 'identity)
                    'core/qualification))
    (test-case "Core profile slots reject a zero-heap Case"
      (let (bounded
            (.o (:: @ +core-case-profile+)
                (heap-limit-bytes 0)
                (live-growth-limit-bytes 0)
                (sample-interval-milliseconds 1)))
        (check-equal? (yuanxu-testing-case-profile? bounded) #t)
        (check-equal?
         (yuanxu-testing-case-profile?
          (.o (:: @ bounded) (heap-limit-bytes -1)))
         #f)
        (check-equal?
         (yuanxu-testing-case-profile?
          (.o (:: @ bounded) (memory-policy 'legacy)))
         #f)
        (check-equal?
         (with-catch
          YuanxuDebugMemoryAnomaly?
          (lambda ()
            (call-with-values
             (lambda ()
               (.call bounded .run bounded "zero-heap Core Case"
                      (lambda () 'unexpected-admission)))
             (lambda (value _receipt) value))))
         #t)))))
