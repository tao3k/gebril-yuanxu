;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite test-case check-equal?)
        (only-in :clan/poo/object .o .cc .get .ref .set!)
        (only-in :clan/poo/type Type. define-type element? validate)
        (only-in :tao3k/yuanxu/types/contracts YuanxuObjectContract.
                 yuanxu-classification-evidence yuanxu-validation-evidence
                 yuanxu-gerbil-type-contract yuanxu-contract-admit
                 yuanxu-validation-evidence-accepted?
                 ClassType InterfaceType Nullable
                 type-gerbil-descriptor type-predicate type-contract-validator))

(export contract-membership-test)

(def contract-membership-test
  (test-suite "Object Contract membership"
    (test-case "an identity check answers membership without validation evidence"
      (def calls 0)
      (def port-prototype (.o))
      (define-type (PortValue @ Type.)
        .element?: (lambda (candidate) (integer? (.get candidate port)))
        .validate: (lambda (candidate) (set! calls (+ calls 1)) candidate))
      (define-type (PortContract @ YuanxuObjectContract.)
        identity: 'test/port
        proto: port-prototype
        value-contract: PortValue
        .identity-member?:
        (lambda (value-type candidate)
          (and (eq? value-type PortValue)
               (integer? (.get candidate port)))))
      (def candidate (.o (:: @ port-prototype) port: 5432))
      (check-equal? (element? PortContract candidate) #t)
      (check-equal? calls 0)
      (check-equal? (element? PortContract (.o port: 5432)) #f)
      (check-equal? calls 0)
      (check-equal? (eq? (validate PortContract candidate) candidate) #t)
      (check-equal? calls 1)
      (.set! PortContract .obligations (lambda (_value _context) '(custom-refusal)))
      (check-equal? (element? PortContract candidate) #f)
      (check-equal? calls 2))
    (test-case "custom admission and normalizers still receive their original input"
      (def port-prototype (.o))
      (def raw (.o (:: @ port-prototype) port: 5432))
      (define-type (SourceValue @ Type.)
        .element?: (lambda (candidate) (integer? (.get candidate port))))
      (define-type (PortContract @ YuanxuObjectContract.)
        identity: 'test/port
        proto: port-prototype
        value-contract: SourceValue
        .identity-member?: (lambda (_type _candidate) #t))
      (def customized
        (.cc PortContract
          '.admit
          (lambda (candidate context)
            (check-equal? (eq? candidate raw) #t)
            (def classification
              (yuanxu-classification-evidence 'test/port candidate #f '() context))
            (yuanxu-validation-evidence customized candidate classification '() #f '() context))))
      (check-equal? (element? customized raw) #f)
      (def calls 0)
      (define-type (NormalizedValue @ SourceValue)
        .validate: (lambda (candidate)
                     (set! calls (+ calls 1))
                     (.cc candidate port: 5433)))
      (def normalized
        (.cc PortContract
          value-contract: NormalizedValue
          '.identity-member?: #f
          '.obligations: (lambda (candidate _context)
                           (if (= (.get candidate port) 5433) '() '(unnormalized)))))
      (check-equal? (element? normalized raw) #t)
      (check-equal? calls 1)
      (check-equal? (.get (validate normalized raw) port) 5433)
      (check-equal? (.get raw port) 5432)
      (check-equal? calls 2))
    (test-case "Gerbil v0.19 class/interface/nullable bridge integrates with Yuanxu contracts"
      (defstruct sample-endpoint (host port) final: #t)
      (interface SampleProbe (probe-host))
      (defmethod {probe-host sample-endpoint}
        (lambda (self) (sample-endpoint-host self)))
      (def ep (make-sample-endpoint "localhost" 5432))
      (def class-contract (yuanxu-gerbil-type-contract 'test/endpoint sample-endpoint::t))
      (def iface-contract (yuanxu-gerbil-type-contract 'test/probe SampleProbe::interface))
      (def nullable-contract (yuanxu-gerbil-type-contract 'test/nullable-endpoint (Nullable (ClassType sample-endpoint::t))))
      (check-equal? (type-gerbil-descriptor class-contract) sample-endpoint::t)
      (check-equal? (type-gerbil-descriptor iface-contract) SampleProbe::interface)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit class-contract ep #f)) #t)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit class-contract "bad" #f)) #f)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit iface-contract ep #f)) #t)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit iface-contract 42 #f)) #f)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit nullable-contract #f #f)) #t)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit nullable-contract ep #f)) #t)
      (check-equal? (yuanxu-validation-evidence-accepted? (yuanxu-contract-admit nullable-contract "bad" #f)) #f)
      (def pred (type-predicate class-contract))
      (check-equal? (pred ep) #t)
      (check-equal? (pred #f) #f)
      (def validator (type-contract-validator class-contract))
      (check-equal? (eq? (validator ep) ep) #t))))
