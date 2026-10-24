;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop Type. define-type TypeError?)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :clan/poo/type String)
        (only-in :yuanxu/object-types/contracts
          YuanxuObjectContract. yuanxu-predicate-contract
          yuanxu-contract-admit yuanxu-validation-evidence-accepted?
          yuanxu-validation-evidence->alist))
(export admission-binding-test)

(def admission-binding-test
  (test-suite "Core admission records its actual Contract"
    (test-case "base, derived and rejected admissions all record their own descriptor"
      (def descriptor
        (yuanxu-predicate-contract 'test/name string? (lambda (_candidate _context) '())))
      (def derived (.cc descriptor))
      (def context (.o revision: 1))
      (for-each
        (lambda (current)
          ;; Exercise the native slot directly as well as the generic entry.
          (def accepted (.call current .admit "web" context))
          (def refused (yuanxu-contract-admit current 7 context))
          (check-equal? (yuanxu-validation-evidence-accepted? accepted) #t)
          (check-equal? (yuanxu-validation-evidence-accepted? refused) #f)
          (check-equal? (eq? (.get accepted admission-contract) current) #t)
          (check-equal? (eq? (.get refused admission-contract) current) #t)
          (check-equal? (eq? (.get accepted context) context) #t)
          ;; Exact references are in-process metadata, not wire reconstruction.
          (check-equal? (assq 'admission-contract
                         (yuanxu-validation-evidence->alist accepted)) #f))
        (list descriptor derived)))

    (test-case "responsibility admission preserves root and nested descriptor references"
      (def leaf
        (yuanxu-predicate-contract 'test/name string? (lambda (_candidate _context) '())))
      (def proto (.o))
      (def descriptor
        (.cc YuanxuObjectContract.
          identity: 'test/profile proto: proto responsibilities: (.o name: leaf)))
      (def context (.o revision: 1))
      (def value (.o (:: @ proto) name: "web"))
      (def accepted (yuanxu-contract-admit descriptor value context))
      (check-equal? (yuanxu-validation-evidence-accepted? accepted) #t)
      (check-equal? (eq? (.get accepted admission-contract) descriptor) #t)
      (def nested (car (.get accepted responsibility-evidence)))
      (check-equal? (eq? (.get nested admission-contract) leaf) #t)
      (check-equal? (.get nested candidate) "web")
      (check-equal? (eq? (.get nested context) context) #t)
      (def missing (yuanxu-contract-admit descriptor (.o (:: @ proto)) context))
      (check-equal? (yuanxu-validation-evidence-accepted? missing) #f)
      (check-equal? (eq? (.get missing admission-contract) descriptor) #t)
      (def missing-child (car (.get missing responsibility-evidence)))
      (check-equal? (eq? (.get missing-child admission-contract) leaf) #t)
      (check-equal? (yuanxu-validation-evidence-accepted? missing-child) #f)
      (check-equal? (.get missing-child responsibility) 'name))

    (test-case "responsibilities consume the checked root once and retain contextual child evidence"
      (def validations 0)
      (def field-validations 0)
      (def seen '())
      (def proto (.o))
      (.def (Parent @ proto name)
        name: "parent" resource: name)
      (def parent-cached (.get Parent resource))
      (.def (raw @ Parent) name: "raw")
      (def checked #f)
      (define-type (Name @ Type.)
        .element?: string?
        .validate:
        (lambda (_value)
          (set! field-validations (+ field-validations 1))
          "checked"))
      (def fields (.cc ObjectContract.
                    required-prototype: proto
                    responsibilities: (.o name: Name resource: String)))
      (define-type (Normalize @ Type.)
        .validate:
        (lambda (value)
          (unless (eq? value raw) (error "unexpected repeated value validation"))
          (set! validations (+ validations 1))
          (set! checked (.call fields .validate value))
          checked))
      ;; The public field Type already owns value checking. This child has
      ;; contextual duties only; it must not repeat the string validator.
      (def leaf (yuanxu-predicate-contract 'test/checked-name (lambda (_value) #t)
                   (lambda (value context)
                     (check-equal? value "checked")
                     '())))
      (def descriptor
        (.cc YuanxuObjectContract.
          identity: 'test/checked-root proto: proto value-contract: Normalize
          responsibilities: (.o name: leaf)))
      (def context
        (.o .contract-obligations:
          (lambda (contract value)
            (set! seen (cons (list contract value) seen))
            '())))
      (def evidence (.call descriptor .admit raw context))
      (check-equal? validations 1)
      (check-equal? field-validations 1)
      (check-equal? (yuanxu-validation-evidence-accepted? evidence) #t)
      (check-equal? (eq? (.get evidence candidate) checked) #t)
      (check-equal? parent-cached "parent")
      (check-equal? (.get raw resource) "raw")
      (check-equal? (.get checked resource) "checked")
      (check-equal? (eq? (.get evidence classification candidate) checked) #t)
      (def nested (car (.get evidence responsibility-evidence)))
      (check-equal? (.get nested candidate) "checked")
      (check-equal? (eq? (.get nested admission-contract) leaf) #t)
      (check-equal? (eq? (.get nested context) context) #t)
      (check-equal? (length seen) 2)
      (check-equal? (eq? (caar seen) descriptor) #t)
      (check-equal? (eq? (cadar seen) checked) #t))

    (test-case "Context refusal applies at root and child without dropping child evidence"
      (def proto (.o))
      (def leaf (yuanxu-predicate-contract 'test/context-name string?
                   (lambda (_value _context) '())))
      (def descriptor
        (.cc YuanxuObjectContract.
          identity: 'test/context-root proto: proto responsibilities: (.o name: leaf)))
      (def value (.o (:: @ proto) name: "web"))
      (for-each
        (lambda (target)
          (def context
            (.o .contract-obligations:
              (lambda (contract _value)
                (if (eq? contract target)
                  (list (.o kind: 'context-refused)) '()))))
          (def evidence (.call descriptor .admit value context))
          (check-equal? (yuanxu-validation-evidence-accepted? evidence) #f)
          (check-equal? (eq? (.get evidence admission-contract) descriptor) #t)
          (def nested (car (.get evidence responsibility-evidence)))
          (check-equal? (eq? (.get nested admission-contract) leaf) #t)
          (check-equal? (eq? (.get nested context) context) #t)
          (check-equal? (yuanxu-validation-evidence-accepted? nested)
                        (not (eq? target leaf))))
        (list descriptor leaf)))

    (test-case "contextual child admission cannot publish a detached normalized child"
      (def proto (.o))
      (def original (.o name: "web"))
      (def replacement (.o name: "changed"))
      (define-type (Rewrite @ Type.)
        .validate: (lambda (_value) replacement))
      (def leaf
        (.cc (yuanxu-predicate-contract 'test/child object?
                (lambda (_value _context) '()))
          value-contract: Rewrite))
      (def descriptor
        (.cc YuanxuObjectContract.
          identity: 'test/root proto: proto responsibilities: (.o service: leaf)))
      (check-exception
        (.call descriptor .admit (.o (:: @ proto) service: original) #f)
        TypeError?))))
