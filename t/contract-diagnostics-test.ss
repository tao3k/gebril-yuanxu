;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object :clan/poo/object-contract
        (only-in :clan/poo/number IntegerRange)
        (only-in :clan/poo/mop validate TypeError?)
        (only-in :std/error Error Error?)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-predicate-contract)
        (only-in :yuanxu/admission/source SourceAdmissionContract.)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export contract-diagnostics-test)

(def contract-diagnostics-test
  (test-suite "Native diagnostics at the contextual admission boundary"
    (yuanxu-test-case "metadata contracts use native predicates without empty callbacks"
      (def Contract (yuanxu-predicate-contract 'test/scope (o?/slots '(payload))))
      (def scope (.o payload: (error "unselected scope payload forced")))
      (check-equal? (.get (.call Contract .admit scope #f) accepted?) #t)
      (check-equal? (.get (.call Contract .admit (.o) #f) accepted?) #f))
    (yuanxu-test-case "shape normalization runs once without a no-op classifier"
      (def calls 0)
      (def diagnoses 0)
      (def Shape
        (.o (:: @ ObjectContract.)
          responsibilities: (.o port: (IntegerRange min: 1 max: 65535))
          (.validate (inherited)
            (lambda (candidate)
              (set! calls (+ calls 1))
              ((inherited) candidate)))
          (.diagnose (inherited)
            (lambda (candidate path)
              (set! diagnoses (+ diagnoses 1))
              ((inherited) candidate path)))))
      (.def (Contract @ YuanxuContract.) identity: 'test/port value-contract: Shape)
      (def evidence (.call Contract .admit (.o port: 5432) #f))
      (check-equal? calls 1)
      (check-equal? diagnoses 1)
      (check-equal? (.get evidence accepted?) #t)
      (check-equal? (eq? (.get evidence admission-contract) Contract) #t)
      (check-equal? (.get evidence candidate port) 5432))
    (yuanxu-test-case "native diagnostics become the same rejection facts"
      (def issue (.o kind: 'port-conflict path: '(port)))
      (.def (Contract @ SourceAdmissionContract.)
        identity: 'test/port
        value-contract:
        (refine (.cc ObjectContract. responsibilities: (.o port: (IntegerRange min: 1 max: 65535)))
                (lambda (_candidate _path) (list issue))))
      (def evidence (.call Contract .admit (.o port: 5433) #f))
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (eq? (car (.get evidence diagnostics)) issue) #t)
      (check-equal? (eq? (car (.get evidence classification diagnostics)) issue) #t))
    (yuanxu-test-case "normalized refusal retains the checked root and native cause"
      (def Port (IntegerRange min: 1 max: 65535))
      (.def (Increment @ Port) .validate: (lambda (value) (+ value 1)))
      (def issue (.o kind: 'normalized-port path: '(port)))
      (def cause #f)
      (.def (Shape @ (refine (.cc ObjectContract. responsibilities: (.o port: Increment))
                        (lambda (value _path)
                          (if (= (.get value port) 5433) (list issue) '()))))
        (.validate (inherited)
          (lambda (value)
            (with-catch (lambda (failure) (set! cause failure) (raise failure))
              (cut (inherited) value)))))
      (.def (Contract @ SourceAdmissionContract.) identity: 'test/normalized value-contract: Shape)
      (def raw (.o port: 5432))
      (def effects 0)
      (def context (.o admit-current: (lambda () (set! effects (+ effects 1)))))
      (def evidence (.call Contract .admit raw context))
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (TypeError? cause) #t)
      (check-equal? (eq? cause (.get evidence cause)) #t)
      (check-equal? (eq? (car (.get evidence diagnostics)) issue) #t)
      (check-equal? (.get evidence candidate port) 5433)
      (check-equal? (.get raw port) 5432)
      (check-equal? effects 0))
    (yuanxu-test-case "refusal conversion does not catch effect or contextual errors"
      (def original (Error "validator effect failed"))
      (.def (Broken @ ObjectContract.) .validate: (lambda (_value) (raise original)))
      (.def (Contract @ SourceAdmissionContract.) identity: 'test/effect value-contract: Broken)
      (check-equal? (eq? original (with-catch values (cut .call Contract .admit (.o) #f))) #t)
      (def typed-cause (with-catch values (cut validate (IntegerRange min: 1) 0)))
      (.def (Contextual @ SourceAdmissionContract.)
        identity: 'test/context value-contract: (.cc ObjectContract.)
        .obligations: (lambda (_value _context) (raise typed-cause)))
      (check-equal? (eq? typed-cause
                        (with-catch values (cut .call Contextual .admit (.o) #f))) #t))
    (yuanxu-test-case "a child prepares its own native refinement after a warm parent"
      (def Shape (.cc ObjectContract. responsibilities: (.o port: (IntegerRange min: 1 max: 65535))))
      (.def (Parent @ SourceAdmissionContract.) identity: 'test/parent value-contract: Shape)
      (check-equal? (.get (.call Parent .admit (.o port: 5432) #f) accepted?) #t)
      (.def (Child @ Parent)
        identity: 'test/child
        value-contract:
        (refine Shape
          (lambda (candidate location)
            (if (= (.get candidate port) 5433) '()
              (list (.o kind: 'child-port path: (append location '(port))))))))
      (check-equal? (.get (.call Child .admit (.o port: 5432) #f) accepted?) #f)
      (check-equal? (.get (.call Child .admit (.o port: 5433) #f) accepted?) #t)
      (check-equal? (.get (.call Parent .admit (.o port: 5432) #f) accepted?) #t))
    (yuanxu-test-case "contextual child obligations remain independent of shape"
      (def calls 0)
      (def issue (.o kind: 'child-policy path: '(port)))
      (.def (Child @ YuanxuContract.)
        identity: 'test/child
        prepared-value-action: (error "context-only child must not prepare a value action")
        .obligations:
        (lambda (_candidate _context)
          (set! calls (+ calls 1)) (list issue)))
      (.def (Root @ YuanxuContract.)
        identity: 'test/root responsibilities: (.o child: Child))
      (def candidate (.o child: (.o port: 5432)))
      (def evidence (.call Root .admit candidate #f))
      (def child (car (.get evidence responsibility-evidence)))
      (check-equal? calls 1)
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (eq? (.get child candidate) (.get candidate child)) #t)
      (check-equal? (eq? (car (.get child diagnostics)) issue) #t)
      ;; A contextual Contract used as a native field Type must not expose a
      ;; shape-only .diagnose that bypasses its own admission obligations.
      (def Shape (.cc ObjectContract. responsibilities: (.o child: Child)))
      (check-exception (validate Shape candidate) TypeError?))
    (yuanxu-test-case "malformed diagnostics are programming errors"
      (.def (Contract @ SourceAdmissionContract.)
        identity: 'test/bad-diagnostic
        value-contract:
        (refine (.cc ObjectContract.)
                (lambda (_candidate _path) '(not-a-diagnostic))))
      (check-exception (.call Contract .admit (.o) #f) Error?))))
