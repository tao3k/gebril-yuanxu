;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Public upstream controls, kept distinct from Core's CLOS calling grammar.
(import (only-in :std/test test-suite check check-equal? check-exception)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :clan/poo/object .o .get .ref)
        (only-in :clan/poo/declaration .declare declaration-forms object<-declaration-forms)
        (only-in :clan/poo/mop .defgeneric Any)
        (only-in :clan/poo/method-declaration MethodDeclaration. standard-combination)
        (prefix-in :clan/poo/method-combination combination.)
        (prefix-in :clan/poo/multimethod multi.))
(export poo-clos-upstream-alignment-test)

;; This native generic preserves Gerbil's optional/keyword/rest grammar; it
;; must not be lowered through the separate CLOS &optional/&key parser.
(.defgeneric (forward-row receiver required (optional #f) label: (label #f) . rest)
  slot: .forward combination: (lambda (parts row) (list parts row)))
(.defgeneric (score receiver units) slot: .score combination: standard-combination)

(def poo-clos-upstream-alignment-test
  (test-suite "Public upstream mechanisms used by Core"
    (yuanxu-test-case "native forwarding retains keyword false and a private rest spine"
      (def receiver (.o .forward: 'parts))
      (def supplied (list 2 3 label: #f 'tail))
      (def result (apply forward-row receiver supplied))
      ;; Gerbil's call row places keywords before the #!rest positional row.
      (check-equal? result '(parts (label: #f #!rest 2 3 tail)))
      (check-equal?
        (apply (lambda (required (optional #f) label: (label #f) . rest)
                 (list required optional label rest))
               (cadr result))
        '(2 3 #f (tail)))
      (set-car! (list-tail (cadr result) 5) 'changed)
      (check-equal? supplied '(2 3 label: #f tail)))
    (yuanxu-test-case "method fragments merge upstream without a Core registry"
      (def events '())
      (def parent
        (.declare MethodDeclaration. (.o)
          (method .score (.o contributions:
            (list (combination.primary (lambda (_next units) (* 10 units))))))))
      (check-equal? (score parent 2) 20)
      (def child
        (object<-declaration-forms MethodDeclaration. (.o)
         (declaration-forms
          (method .score (.o contributions:
            (list (combination.before (lambda (_units) (set! events (cons 'before events)))))))
          (method .score (.o contributions:
            (list (combination.primary (lambda (next units) (+ units (next))))))))
         supers: (list parent)))
      (check-equal? (score child 2) 22)
      (check-equal? events '(before))
      (check-equal? (score parent 2) 20))
    (yuanxu-test-case "separate upstream multimethods preserve two independent axes"
      ;; Symbolic dispatch names are deliberately explicit here. They are not
      ;; an adapter proving Core class/eql identity or next-method equivalence.
      (def generic
        (multi.make (list Any Any) Any
          (lambda (arguments) (map list arguments))))
      (def broad (multi.register generic (list (multi.prototype 'web) multi.any)
                   (lambda (_service _backend) 'broad)))
      (def exact (multi.register broad (list (multi.prototype 'web) (multi.prototype 'aws))
                   (lambda (_service _backend) 'exact)))
      (defvalues (exact-result _exact-cache) (multi.call exact 'web 'aws))
      (defvalues (broad-result _broad-cache) (multi.call broad 'web 'aws))
      (check-equal? exact-result 'exact)
      (check-equal? broad-result 'broad))))
