;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .o .ref .call .cc object-slots object-%slot-funs
                 $constant-slot-spec? object-protocol-set!)
        (only-in :yuanxu/object-types/ports Port valid-port?)
        (only-in :clan/poo/mop define-type element?)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer)
        (only-in :yuanxu/observability/memory
                 call-with-yuanxu-debug-memory-case-watchdog
                 yuanxu-debug-memory-policy YuanxuDebugDurationAnomaly?
                 YuanxuDebugMemoryAnomaly-receipt YuanxuDebugDurationAnomaly-receipt)
        (only-in :yuanxu/object-types/contracts
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

;; The field intentionally has the same spelling as the prototype binding.
(defpoo-object-family
  (prototype FamilyData family-data? family-data?)
  (constructor make-family-data (value FamilyData) (optional optional))
  (accessors (family-value FamilyData))
  (projections))

(def +core-case-profile+
  (.o (:: @ yuanxu-default-testing-case-profile)
      (identity 'core/qualification)
      (max-duration-milliseconds 2000)))

(def core-test
  (test-suite "Core"
    (test-case "family values use runtime constants with hygienic ancestry and stable methods"
      (def effects 0)
      (def events '())
      (object-protocol-set! FamilyData
        (.o compute-slot: (lambda (_self next name)
                            (set! events (cons name events)) (next))))
      (def value (make-family-data (begin (set! effects (1+ effects)) 41) #f))
      (check-equal? effects 1)
      (check-equal? (family-data? value) #t)
      (check-equal? (family-value value) 41)
      (def first-events (reverse events))
      ;; Gerbil tables have independent random seeds. Check the EXACT runtime
      ;; traversal of this receiver, not another receiver's accidental order.
      (check-equal? first-events (map car (hash->list (object-%slot-funs value))))
      (def method (hash-get (object-%slot-funs value) 'FamilyData))
      (check-equal? (family-value value) 41)
      (check-equal? (eq? method (hash-get (object-%slot-funs value) 'FamilyData)) #t)
      (for-each (lambda (entry) (check-equal? ($constant-slot-spec? (cdr entry)) #t)) (object-slots value))
      (set! events '())
      (def reference (.o (:: @ FamilyData) (FamilyData 41) (optional #f)))
      (check-equal? (family-value reference) 41)
      (check-equal? (reverse events) (map car (hash->list (object-%slot-funs reference))))
      (check-equal? (.ref value 'optional) #f)
      (def child (.cc value FamilyData: 42))
      (check-equal? (family-value child) 42)
      (check-equal? (family-value value) 41)
      (check-equal? effects 1))
    (test-case "runtime contracts retain prototype ancestry"
      (let* ((proto (.ref CoreNameContract 'proto))
             (value (.o (:: @ proto) name: 'core)))
        (check-equal? (element? CoreNameContract value) #t)
        (check-equal? (yuanxu-validation-evidence-accepted?
                       (yuanxu-contract-admit CoreNameContract value #f))
                      #t)
        (check-equal? (element? CoreNameContract (.o name: 'core)) #f)))
    (test-case "shared endpoint ports retain the complete range constraint"
      (for-each (lambda (value) (check-equal? (element? Port value) #t)) '(1 5432 65535))
      (for-each (lambda (value) (check-equal? (valid-port? value) #f))
        '(0 -1 65536 5432.0 "5432" #f)))
    (test-case "object-family projection stays POO"
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
    (test-case "watchdog diagnostics wait for the interrupted read scope to unwind"
      (def reads 0)
      (def seen #f)
      (def on-stop raise)
      (def (interrupted-body)
        (with-catch
          (lambda (failure)
            (set! seen failure)
            (on-stop failure))
          (lambda ()
            (call-with-slot-read-observer
              (lambda (_read)
                (set! reads (1+ reads))
                (error "diagnostic reentered interrupted read scope"))
              (lambda () (thread-sleep! 0.05))))))
      (def (stopped policy duration)
        (set! seen #f)
        (def failure (with-catch values
          (lambda ()
            (call-with-yuanxu-debug-memory-case-watchdog policy 'read-scope
              interrupted-body max-duration-milliseconds: duration))))
        (check-equal? (eq? failure seen) #t)
        (def receipt
          (if (YuanxuDebugMemoryAnomaly? failure)
            (YuanxuDebugMemoryAnomaly-receipt failure)
            (YuanxuDebugDurationAnomaly-receipt failure)))
        (check-equal? (.ref receipt 'accepted?) #f)
        (check-equal? (.ref receipt 'phase) 'read-scope)
        (check-equal? (.ref receipt 'reason)
          (if (YuanxuDebugMemoryAnomaly? failure) 'heap-limit-exceeded 'duration-exceeded))
        failure)
      (check-equal?
        (YuanxuDebugMemoryAnomaly?
          (stopped (yuanxu-debug-memory-policy 'test/memory
                     heap-limit-bytes: 0 live-growth-limit-bytes: 0
                     sample-interval-milliseconds: 1) 1000)) #t)
      (check-equal?
        (YuanxuDebugDurationAnomaly?
          (stopped (yuanxu-debug-memory-policy 'test/duration
                     heap-limit-bytes: (.ref +core-case-profile+ 'heap-limit-bytes)
                     live-growth-limit-bytes: (.ref +core-case-profile+ 'live-growth-limit-bytes)
                     sample-interval-milliseconds: 1) 5)) #t)
      (set! on-stop (lambda (_failure) 'ignored))
      (check-equal?
        (YuanxuDebugMemoryAnomaly?
          (stopped (yuanxu-debug-memory-policy 'test/swallowed
                     heap-limit-bytes: 0 live-growth-limit-bytes: 0
                     sample-interval-milliseconds: 1) 1000)) #t)
      (set! on-stop (lambda (_failure) (error "nested guard replaced the stop")))
      (check-equal?
        (YuanxuDebugDurationAnomaly?
          (stopped (yuanxu-debug-memory-policy 'test/replaced
                     heap-limit-bytes: (.ref +core-case-profile+ 'heap-limit-bytes)
                     live-growth-limit-bytes: (.ref +core-case-profile+ 'live-growth-limit-bytes)
                     sample-interval-milliseconds: 1) 5)) #t)
      (check-equal? reads 0))
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
