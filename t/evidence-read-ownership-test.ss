;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads replay-slot-reads!
                 slot-read-key slot-read-dependencies)
        (only-in :yuanxu/object-family/read-projection call-with-owned-read-projection
                 owned-read-copy! owned-read-derived!)
        (only-in :clan/poo/validation-rebinding rebind-validation)
        (only-in :clan/poo/mop Type. define-type validate object-read-issued?)
        (only-in :yuanxu/module-system/types ModuleSourceRoleContract)
        (only-in :yuanxu/module-system/authoring/roles TypesSourceRole.)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :yuanxu/object-types/contracts yuanxu-classification-evidence yuanxu-validation-evidence
                 yuanxu-classification-evidence? yuanxu-validation-evidence?
                 YuanxuContract. yuanxu-contract-admit)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export evidence-read-ownership-test)
(def (original-read-graph? reads)
  (def seen (make-hash-table-eq))
  (def (original? read)
    (or (hash-key? seen read)
        (and (object-read-issued? read)
             (not (eq? (slot-read-key read) 'owned-call/full))
             (begin
               (hash-put! seen read #t)
               (andmap original? (slot-read-dependencies read))))))
  (and (pair? reads) (andmap original? reads)))
(def evidence-read-ownership-test
  (test-suite "Native evidence read ownership"
    (yuanxu-test-case "receipts retain actual candidate Contract Context and child identities"
      (def candidate (.o port: 443))
      (def context (.o generation: 'current))
      (def contract (.o identity: 'actual-contract))
      (def diagnostics (list '(notice retained)))
      (def children (list (.o child: #t)))
      (def classification
        (yuanxu-classification-evidence 'actual-type candidate 'truthy diagnostics context))
      (def evidence
        (yuanxu-validation-evidence contract candidate classification children
          #f diagnostics context))
      (for-each
        (lambda (value)
          (check-equal? (eq? (.get value candidate) candidate) #t)
          (check-equal? (eq? (.get value context) context) #t)
          (check-equal? (eq? (.get value diagnostics) diagnostics) #t))
        (list classification evidence))
      (check-equal? (.get classification accepted?) #t)
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (yuanxu-classification-evidence? classification) #t)
      (check-equal? (yuanxu-validation-evidence? evidence) #t)
      (check-equal? (eq? (.get evidence admission-contract) contract) #t)
      (check-equal? (eq? (.get evidence classification) classification) #t)
      (check-equal? (eq? (.get evidence obligation-evidence) children) #t)
      (def clone (.cc evidence 'responsibility-evidence children))
      (check-equal? (eq? (.get clone candidate) candidate) #t)
      (check-equal? (eq? (.get clone responsibility-evidence) children) #t))
    (yuanxu-test-case "receipts remain original replay dependencies after collection"
      (def witness (make-hash-table-eq weak-values: #t))
      (def policy (.o accepted: #t))
      (def Root
        (.o answer:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def receipt
                (yuanxu-classification-evidence 'fixture (.get policy accepted) #t '() #f))
              (hash-put! witness 'temporary receipt)
              (.get receipt candidate)))))
      (check-equal? (.get Root answer) #t)
      (yuanxu-debug-memory-snapshot 'receipt-collected collect?: #t)
      (check-equal? (object? (hash-get witness 'temporary)) #t)
      (.put! policy 'accepted #f)
      (check-exception (.get Root answer) error?)
      (def Held
        (.o receipt:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def value (yuanxu-classification-evidence 'fixture (.o) #t '() #f))
              (.get value accepted?)
              value))))
      (def value (.get Held receipt))
      (.put! value 'accepted? #f)
      (yuanxu-debug-memory-snapshot 'live-receipt-invalidated collect?: #t)
      (check-exception (.get Held receipt) error?))
    (yuanxu-test-case "open obligations Context MOP and borrowed copies keep complete traces"
      (for-each
        (lambda (axis)
          (def witness (make-hash-table-eq weak-values: #t))
          (def Contract
            (.o (:: @ YuanxuContract.) identity: 'fixture
              .classify:
              (lambda (candidate context)
                (def receipt (yuanxu-classification-evidence 'fixture candidate #t '() context))
                (hash-put! witness 'receipt receipt)
                receipt)))
          (when (eq? axis 'obligations)
            (.put! Contract '.obligations (lambda (_candidate _context) '())))
          (when (eq? axis 'mop) (object-protocol-set! Contract (.o)))
          (def Context
            (and (eq? axis 'context)
                 (.o .contract-obligations: (lambda (_contract _candidate) '()))))
          (def borrowed (yuanxu-classification-evidence 'fixture (.o) #t '() #f))
          (def Root
            (.o answer:
              (call-with-owned-read-projection '() (lambda () #t)
                (lambda ()
                  (def receipt
                    (if (eq? axis 'borrowed)
                      (owned-read-copy! borrowed (.cc borrowed 'diagnostics '()))
                      (yuanxu-contract-admit Contract (.o) Context)))
                  (.get receipt accepted?)))))
          (defvalues (answer reads)
            (%call-with-recorded-slot-reads (lambda () (.get Root answer))))
          (check-equal? answer #t)
          (check-equal? (original-read-graph? reads) #t)
          (yuanxu-debug-memory-snapshot 'open-receipt-retained collect?: #t)
          (unless (eq? axis 'borrowed)
            (check-equal? (object? (hash-get witness 'receipt)) #t)))
        '(obligations context mop borrowed)))
    (yuanxu-test-case "a changed constructor generation cannot be weakened"
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (def receipt (yuanxu-classification-evidence 'fixture (.o) #t '() #f))
                (.get receipt accepted?)
                (.put! receipt 'changed-after-read #t)
                #t)))))
      (check-equal? (original-read-graph? reads) #t)
      (check-exception (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))
    (yuanxu-test-case "validation keeps original receivers and all parent policy"
      (def witness (make-hash-table-eq weak-values: #t))
      (def base (.o port: 443))
      (def candidate (.o (:: @ base) label: 'configured))
      (def validations 0)
      (def Root
        (.o answer:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def checked
                (rebind-validation candidate
                  (list (cons 'port
                    (lambda (original receiver)
                      (set! validations (+ validations 1))
                      (owned-read-derived! receiver)
                      (hash-put! witness 'checked receiver)
                      original)))))
              (check-equal? (eq? checked candidate) #t)
              (.get checked port)))))
      (check-equal? (.get Root answer) 443)
      (check-equal? validations 1)
      (yuanxu-debug-memory-snapshot 'native-validation-scratch-collected collect?: #t)
      (check-equal? (object? (hash-get witness 'checked)) #t)
      ;; Even an unread transitive parent field is part of the conservative
      ;; native parent-generation guard; mutation-and-restore cannot renew it.
      (.put! base 'policy 'changed)
      (.put! base 'policy 'restored)
      (check-exception (.get Root answer) error?))
    (yuanxu-test-case "parent edits during validation retain full original support"
      (def candidate (.o port: 443))
      (defvalues (_result reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (def result
                  (rebind-validation candidate
                    (list (cons 'port
                      (lambda (original receiver)
                        (owned-read-derived! receiver) original)))))
                (.put! candidate 'policy 'changed-after-validation)
                result)))))
      (check-equal? (original-read-graph? reads) #t)
      (check-exception (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))
    (yuanxu-test-case "native checked receiver with a MOP ancestor keeps full support"
      (def parent (.o port: 443))
      (object-protocol-set! parent (.o))
      (defvalues (_result reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (rebind-validation parent
                  (list (cons 'port
                    (lambda (original receiver)
                      (owned-read-derived! receiver) original)))))))))
      (check-equal? (original-read-graph? reads) #t))
    (yuanxu-test-case "normalized native checked receivers remain live original evidence"
      (def candidate (.o port: 443))
      (def validations 0)
      (def Root
        (.o checked:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (rebind-validation candidate
                (list (cons 'port
                  (lambda (original receiver)
                    (set! validations (+ validations 1))
                    (owned-read-derived! receiver)
                    (+ original 1)))))))))
      (def checked (.get Root checked))
      (check-equal? (eq? candidate checked) #f)
      (check-equal? (.get checked port) 444)
      (check-equal? validations 1)
      (.put! checked 'port 445)
      (yuanxu-debug-memory-snapshot 'normalized-checked-invalidated collect?: #t)
      (check-exception (.get Root checked) error?))
    (yuanxu-test-case "cached parent Role validation does not freeze a derived field Contract"
      (def parent (.get ModuleSourceRoleContract value-contract))
      (check-equal? (eq? (validate parent TypesSourceRole.) TypesSourceRole.) #t)
      (def calls 0)
      (define-type (RecommendedForms @ Type.)
        .element?: list?
        .validate: (lambda (value) (set! calls (+ calls 1)) (append value '(custom-form))))
      (def fields (.cc (.get parent responsibilities) 'recommended-forms RecommendedForms))
      (def child (.cc parent 'responsibilities fields))
      (def checked
        (call-with-owned-read-projection '() (lambda () #t)
          (lambda () (validate child TypesSourceRole.))))
      (check-equal? (eq? checked TypesSourceRole.) #f)
      (check-equal? (.get checked recommended-forms)
        (append (.get TypesSourceRole. recommended-forms) '(custom-form)))
      (check-equal? calls 1))
    (yuanxu-test-case "late Contract name lookup keeps original identity and native invalidation"
      (def original (.o identity: 'before))
      (def replacement (.o identity: 'same-name))
      (def candidate (.o port: 443))
      (def classification (yuanxu-classification-evidence 'type candidate #t '() #f))
      (def evidence
        (yuanxu-validation-evidence original candidate classification '() #t '() #f))
      (.put! original 'identity 'after)
      (def clone (.cc evidence 'admission-contract replacement))
      (check-equal? (.get clone contract-identity) 'after)
      (check-equal? (eq? (.get clone admission-contract) replacement) #t)
      ;; Storage compatibility does not certify a retargeted receipt.
      (check-equal? (yuanxu-validation-evidence? clone) #f)
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads (lambda () (.get evidence contract-identity))))
      (.put! original 'identity 'changed-after-read)
      (check-exception
        (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))))
