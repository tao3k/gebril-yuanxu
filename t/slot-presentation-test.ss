;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .all-slots .def .get .o)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/slot-presentation
                 yuanxu-slot-view
                 yuanxu-slot-presentation))

(export slot-presentation-test)

(.def RootValue
  (entries ? (.o base: 'base)))

(.def (RefinedValue @ RootValue)
  (entries =>.+ (.o added: 'added)))

(def sources
  (.o refined: (.o prototype: RefinedValue
                   source-path: "yuanxu/t/slot-presentation-test.ss"
                   source-line: 17)
      root: (.o prototype: RootValue
                source-path: "yuanxu/t/slot-presentation-test.ss"
                source-line: 14)))

(def slot-presentation-test
  (test-suite "POO slot presentation"
    (yuanxu-test-case "default view evaluates the POO slot"
      (let (presentation
            (yuanxu-slot-presentation RefinedValue 'entries))
        (check-equal? (.all-slots presentation) '(effective-value))
        (check-equal? (.get (.get presentation effective-value) base) 'base)
        (check-equal? (.get (.get presentation effective-value) added) 'added)))

    (yuanxu-test-case "source view follows prototype declarations"
      (let (view (yuanxu-slot-view RefinedValue 'entries sources))
        (check-equal? (.get view provenance) '(refined root))
        (check-equal?
         (map (lambda (step) (.get step mode))
              (.get view composition-chain))
         '(super-aware default))
        (check-equal?
         (.get (car (.get view declaration-sources)) source-path)
         "yuanxu/t/slot-presentation-test.ss")))

    (yuanxu-test-case "missing provenance and unknown disclosure fail closed"
      (check-exception
       (yuanxu-slot-view
        RefinedValue 'entries
        (.o refined: (.get sources refined)))
       true)
      (check-exception
       (yuanxu-slot-presentation RefinedValue 'entries 'unknown)
       true))))
