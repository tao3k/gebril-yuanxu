;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :clan/poo/object .o .ref)
        (only-in :std/test test-suite check-equal?)
        :yuanxu/contribution/objects)
(export contribution-contract-test)

(def sample
  (make-contribution "test/sample" "1" "test-owner"
                     (.o value: 42) '(test-facet) '(test-read)))

(def contribution-contract-test
  (test-suite "Core POO contribution contract"
    (yuanxu-test-case "admission preserves POO values without execution"
      (let (receipt (admit-contributions (list sample) '(test-read)))
        (check-equal? (.ref receipt 'accepted?) #t)
        (check-equal? (eq? (car (.ref receipt 'selected)) sample) #t)
        (check-equal? (.ref receipt 'runtime-executed?) #f)))
    (yuanxu-test-case "missing capabilities and duplicate identities fail closed"
      (check-equal? (.ref (admit-contributions (list sample) '()) 'accepted?) #f)
      (check-equal? (.ref (admit-contributions (list sample sample) '(test-read))
                         'accepted?) #f))
    (yuanxu-test-case "invalid shape and unsupported contract fail closed"
      (check-equal? (.ref (admit-contributions (list (.o)) '()) 'accepted?) #f)
      (check-equal? (.ref (admit-contributions
                          (list (.o (:: @ sample) core-contract: 'future))
                          '(test-read)) 'reasons)
                    '(incompatible-core-contract)))))
