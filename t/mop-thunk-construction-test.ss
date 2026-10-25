;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Consumer boundary of the actual native MOP, not a replacement evaluator.
(import :std/test :clan/poo/object :clan/poo/inheritance-hooks)
(export mop-thunk-construction-test)
(def mop-thunk-construction-test
  (test-suite "Native construction identity and observation boundaries"
    (test-case "hooks precede value demand and observe one stable standard function"
      (def events '())
      (def bodies 0)
      (def protocol
        (.o compute-slot:
          (lambda (receiver next slot)
            (let (standard (next))
              (check-equal? (eq? standard (next)) #t)
              (set! events (cons (list slot standard receiver) events))
              standard))))
      (def baseline (.o port: 5432 unused: (begin (set! bodies (1+ bodies)) 'unused)))
      (def parent (with-inheritance-hooks protocol baseline))
      (instantiate-object! parent)
      (check-equal? bodies 0)
      (check-equal? (.ref/cached parent 'port) #f)
      (check-equal? (.ref/cached parent 'unused) #f)
      ;; The native hash enumeration supplies the actual schedule; declaration
      ;; or prototype order is NOT assumed to be the hook execution order.
      (let* ((trace (reverse events))
             (port-function (cadr (assq 'port trace))))
        (check-equal? (map car trace) (map car (hash->list (object-%slot-funs parent))))
        (check-equal? (length trace) 2)
        (check-equal? (and (assq 'unused trace) #t) #t)
        (check-equal? (eq? port-function (hash-ref (object-%slot-funs parent) 'port)) #t)
        (check-equal? (.get parent port) 5432)
        (check-equal? (.get parent port) 5432)
        (check-equal? bodies 0)
        (check-equal? (eq? port-function (hash-ref (object-%slot-funs parent) 'port)) #t)
        (check-equal? (length events) 2)
        (.def (child @ parent) port: 5433)
        (check-equal? (.get child port) 5433)
        (check-equal? (.get parent port) 5432)
        (check-equal? (eq? port-function (hash-ref (object-%slot-funs child) 'port)) #f)
        (check-equal? bodies 0)))
    (test-case "hook-free objects still expose functions for unforced slots"
      (def bodies 0)
      (def source (.o port: 5432 unused: (begin (set! bodies (1+ bodies)) 'unused)))
      (instantiate-object! source)
      (check-equal? (object-protocol source) #f)
      (check-equal? bodies 0)
      (check-equal? (.ref/cached source 'unused) #f)
      (let (unforced (hash-ref (object-%slot-funs source) 'unused))
        (check-equal? (procedure? unforced) #t)
        (check-equal? (.get source port) 5432)
        (check-equal? (eq? unforced (hash-ref (object-%slot-funs source) 'unused)) #t)
        (check-equal? bodies 0)))
    (test-case "an unselected construction-hook refusal precedes selected value delivery"
      (def cause (list 'unselected-construction-refused))
      (def bodies 0)
      (def protocol
        (.o compute-slot:
          (lambda (_ next slot)
            (if (eq? slot 'unused) (raise cause) (next)))))
      (def source
        (with-inheritance-hooks protocol
          (.o port: (begin (set! bodies (1+ bodies)) 5432) unused: 'unused)))
      (let (failure (with-catch values (lambda () (.get source port))))
        (check-equal? (eq? failure cause) #t)
        (check-equal? bodies 0)
        (check-equal? (object-%instance source) #f)
        (check-equal? (object-%slot-funs source) #f)))))
