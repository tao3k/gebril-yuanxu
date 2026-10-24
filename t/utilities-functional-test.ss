;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: behavior checks for generic functional utilities.

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         (only-in :std/test
                 check-equal?
                 test-suite)
        (only-in :yuanxu/utilities/functional
                 yuanxu-fold-right
                 yuanxu-map
                 yuanxu-find
                 yuanxu-filter-map
                 yuanxu-append-map
                 yuanxu-any?
                 yuanxu-all?
                 yuanxu-set-subset?
                 yuanxu-stable-duplicates
                 yuanxu-list-of?
                 yuanxu-predicate-and
                 yuanxu-predicate-or
                 yuanxu-predicate-exactly-one
                 yuanxu-alist-ref/default
                 yuanxu-alist-select
                 yuanxu-alist-delete-key
                 yuanxu-alist-merge-right))

(export utilities-functional-test)

;; : TestSuite
(def utilities-functional-test
  (test-suite "utilities functional helpers"
    (yuanxu-test-case "delegates core list operations to std functional algorithms"
      (check-equal?
       (yuanxu-fold-right cons [] '(a b c))
       '(a b c))
      (check-equal?
       (yuanxu-map
        (lambda (value)
          (* value 2))
        '(1 2 3))
       '(2 4 6))
      (check-equal?
       (yuanxu-find odd? '(2 4 5 6))
       5)
      (check-equal?
       (yuanxu-filter-map
        (lambda (value)
          (and (odd? value) value))
        '(1 2 3 4 5))
       '(1 3 5))
      (check-equal?
       (yuanxu-append-map
        (lambda (value)
          (list value value))
        '(a b c))
       '(a a b b c c)))
    (yuanxu-test-case "composes predicates without duplicating loop code"
      (let ((positive-even?
             (yuanxu-predicate-and (list integer? positive? even?)))
            (string-or-symbol?
             (yuanxu-predicate-or (list string? symbol?)))
            (exact-string-or-symbol?
             (yuanxu-predicate-exactly-one (list string? symbol?))))
        (check-equal? (yuanxu-any? symbol? '(1 "two" three)) #t)
        (check-equal? (yuanxu-all? integer? '(1 2 3)) #t)
        (check-equal? (yuanxu-list-of? symbol? '(alpha beta)) #t)
        (check-equal? (yuanxu-list-of? symbol? 'not-a-list) #f)
        (check-equal? (positive-even? 4) #t)
        (check-equal? (positive-even? -4) #f)
        (check-equal? (string-or-symbol? "agent") #t)
        (check-equal? (string-or-symbol? 'agent) #t)
        (check-equal? (string-or-symbol? 42) #f)
        (check-equal? (exact-string-or-symbol? "agent") #t)
        (check-equal? (exact-string-or-symbol? 'agent) #t)
        (check-equal? (exact-string-or-symbol? 42) #f)))
    (yuanxu-test-case "extracts stable duplicate values with hash-backed std algorithms"
      (check-equal?
       (yuanxu-stable-duplicates '(alpha beta alpha gamma beta alpha))
       '(alpha beta))
      (check-equal?
       (yuanxu-stable-duplicates '((a . 1) (b . 2) (a . 1)))
       '((a . 1))))
    (yuanxu-test-case "checks list-shaped set inclusion through one hash index"
      (check-equal? (yuanxu-set-subset? '(alpha gamma)
                                          '(alpha beta gamma))
                    #t)
      (check-equal? (yuanxu-set-subset? '(alpha missing)
                                          '(alpha beta gamma))
                    #f)
      (check-equal? (yuanxu-set-subset? '() '(alpha)) #t))
    (yuanxu-test-case "projects and merges association lists deterministically"
      (let ((base '((owner . kernel)
                    (budget . 100)
                    (mode . strict)))
            (override '((budget . 50)
                        (doctor . enabled))))
        (check-equal?
         (yuanxu-alist-ref/default base 'missing 'fallback)
         'fallback)
        (check-equal?
         (yuanxu-alist-select '(mode owner missing) base)
         '((mode . strict) (owner . kernel)))
        (check-equal?
         (yuanxu-alist-delete-key 'budget base)
         '((owner . kernel) (mode . strict)))
        (check-equal?
         (yuanxu-alist-merge-right base override)
         '((budget . 50)
           (doctor . enabled)
           (owner . kernel)
           (mode . strict)))))))
