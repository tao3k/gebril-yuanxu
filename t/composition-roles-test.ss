;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import :std/test
        :clan/poo/object
        :yuanxu/composition/roles
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))

(export composition-roles-test)

(def composition-roles-test
  (test-suite "Shared native role composition"
    (yuanxu-test-case "constant overlays retain native leftmost precedence"
      (let* ((left (object<-alist '((value . left))))
             (right (object<-alist '((value . right) (other . retained))))
             (overlay (role-instance-overlay left right))
             (mixed (role-compose left right)))
        (check (.get overlay value) => (.get mixed value))
        (check (.get overlay other) => 'retained)))
    (yuanxu-test-case "computed slots are refused by the constant fast lane"
      (let (computed (.o value: 1 result: (+ value 1)))
        (check (role-instance-overlay-compatible? computed) => #f)
        (check-exception (role-instance-overlay computed) exception?)
        (check (.get (role-compose computed) result) => 2)))))
