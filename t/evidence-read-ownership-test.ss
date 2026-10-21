;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads replay-slot-reads!
                 slot-read-key slot-read-dependencies)
        (only-in :core/object-family/read-projection call-with-owned-read-projection
                 owned-read-copy! owned-read-derived!)
        (only-in :clan/poo/validation-rebinding rebind-validation)
        (only-in :clan/poo/mop Type. define-type validate)
        (only-in :core/module-system/types ModuleSourceRoleContract)
        (only-in :core/module-system/authoring/roles TypesSourceRole.)
        (only-in :core/observability/memory poo-flow-debug-memory-snapshot)
        (only-in :core/types poo-flow-classification-evidence poo-flow-validation-evidence
                 poo-flow-classification-evidence? poo-flow-validation-evidence?
                 PooFlowContract. poo-flow-contract-admit)
        (only-in :core/observability/testing-case poo-flow-test-case))
(export evidence-read-ownership-test)
(def (has-full-bundle? reads)
  (def seen (make-hash-table-eq))
  (def (find read)
    (and (not (hash-key? seen read))
         (begin (hash-put! seen read #t)
           (or (eq? (slot-read-key read) 'owned-call/full)
               (ormap find (slot-read-dependencies read))))))
  (if (ormap find reads) #t #f))
(def evidence-read-ownership-test
  (test-suite "Native evidence read ownership"
    (poo-flow-test-case "receipts retain actual candidate Contract Context and child identities"
      (def candidate (.o port: 443))
      (def context (.o generation: 'current))
      (def contract (.o identity: 'actual-contract))
      (def diagnostics (list '(notice retained)))
      (def children (list (.o child: #t)))
      (def classification
        (poo-flow-classification-evidence 'actual-type candidate 'truthy diagnostics context))
      (def evidence
        (poo-flow-validation-evidence contract candidate classification children
          #f diagnostics context))
      (for-each
        (lambda (value)
          (check-equal? (eq? (.get value candidate) candidate) #t)
          (check-equal? (eq? (.get value context) context) #t)
          (check-equal? (eq? (.get value diagnostics) diagnostics) #t))
        (list classification evidence))
      (check-equal? (.get classification accepted?) #t)
      (check-equal? (.get evidence accepted?) #f)
      (check-equal? (poo-flow-classification-evidence? classification) #t)
      (check-equal? (poo-flow-validation-evidence? evidence) #t)
      (check-equal? (eq? (.get evidence admission-contract) contract) #t)
      (check-equal? (eq? (.get evidence classification) classification) #t)
      (check-equal? (eq? (.get evidence obligation-evidence) children) #t)
      (def clone (.cc evidence 'responsibility-evidence children))
      (check-equal? (eq? (.get clone candidate) candidate) #t)
      (check-equal? (eq? (.get clone responsibility-evidence) children) #t))
    (poo-flow-test-case "returned receipts keep original replay while unused receipts can collect"
      (def witness (make-hash-table-eq weak-values: #t))
      (def policy (.o accepted: #t))
      (def Root
        (.o answer:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def receipt
                (poo-flow-classification-evidence 'fixture (.get policy accepted) #t '() #f))
              (hash-put! witness 'temporary receipt)
              (.get receipt candidate)))))
      (check-equal? (.get Root answer) #t)
      (poo-flow-debug-memory-snapshot 'receipt-collected collect?: #t)
      (check-equal? (hash-get witness 'temporary) #f)
      (.put! policy 'accepted #f)
      (check-exception (.get Root answer) error?)
      (def Held
        (.o receipt:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def value (poo-flow-classification-evidence 'fixture (.o) #t '() #f))
              (.get value accepted?)
              value))))
      (def value (.get Held receipt))
      (.put! value 'accepted? #f)
      (poo-flow-debug-memory-snapshot 'live-receipt-invalidated collect?: #t)
      (check-exception (.get Held receipt) error?))
    (poo-flow-test-case "open obligations Context MOP and borrowed copies keep complete traces"
      (for-each
        (lambda (axis)
          (def witness (make-hash-table-eq weak-values: #t))
          (def Contract
            (.o (:: @ PooFlowContract.) identity: 'fixture
              .classify:
              (lambda (candidate context)
                (def receipt (poo-flow-classification-evidence 'fixture candidate #t '() context))
                (hash-put! witness 'receipt receipt)
                receipt)))
          (when (eq? axis 'obligations)
            (.put! Contract '.obligations (lambda (_candidate _context) '())))
          (when (eq? axis 'mop) (object-protocol-set! Contract (.o)))
          (def Context
            (and (eq? axis 'context)
                 (.o .contract-obligations: (lambda (_contract _candidate) '()))))
          (def borrowed (poo-flow-classification-evidence 'fixture (.o) #t '() #f))
          (def Root
            (.o answer:
              (call-with-owned-read-projection '() (lambda () #t)
                (lambda ()
                  (def receipt
                    (if (eq? axis 'borrowed)
                      (owned-read-copy! borrowed (.cc borrowed 'diagnostics '()))
                      (poo-flow-contract-admit Contract (.o) Context)))
                  (.get receipt accepted?)))))
          (defvalues (answer reads)
            (%call-with-recorded-slot-reads (lambda () (.get Root answer))))
          (check-equal? answer #t)
          (check-equal? (has-full-bundle? reads) #t)
          (poo-flow-debug-memory-snapshot 'open-receipt-retained collect?: #t)
          (unless (eq? axis 'borrowed)
            (check-equal? (object? (hash-get witness 'receipt)) #t)))
        '(obligations context mop borrowed)))
    (poo-flow-test-case "a changed constructor generation cannot be weakened"
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda ()
                (def receipt (poo-flow-classification-evidence 'fixture (.o) #t '() #f))
                (.get receipt accepted?)
                (.put! receipt 'changed-after-read #t)
                #t)))))
      (check-equal? (has-full-bundle? reads) #t)
      (check-exception (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))
    (poo-flow-test-case "unchanged native validation scratch collects but all parent policy remains"
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
      (poo-flow-debug-memory-snapshot 'native-validation-scratch-collected collect?: #t)
      (check-equal? (hash-get witness 'checked) #f)
      ;; Even an unread transitive parent field is part of the conservative
      ;; native parent-generation guard; mutation-and-restore cannot renew it.
      (.put! base 'policy 'changed)
      (.put! base 'policy 'restored)
      (check-exception (.get Root answer) error?))
    (poo-flow-test-case "parent edits during validation retain full original support"
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
      (check-equal? (has-full-bundle? reads) #t)
      (check-exception (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))
    (poo-flow-test-case "native checked receiver with a MOP ancestor keeps full support"
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
      (check-equal? (has-full-bundle? reads) #t))
    (poo-flow-test-case "normalized native checked receivers remain live original evidence"
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
      (poo-flow-debug-memory-snapshot 'normalized-checked-invalidated collect?: #t)
      (check-exception (.get Root checked) error?))
    (poo-flow-test-case "cached parent Role validation does not freeze a derived field Contract"
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
    (poo-flow-test-case "late Contract name lookup keeps original identity and native invalidation"
      (def original (.o identity: 'before))
      (def replacement (.o identity: 'same-name))
      (def candidate (.o port: 443))
      (def classification (poo-flow-classification-evidence 'type candidate #t '() #f))
      (def evidence
        (poo-flow-validation-evidence original candidate classification '() #t '() #f))
      (.put! original 'identity 'after)
      (def clone (.cc evidence 'admission-contract replacement))
      (check-equal? (.get clone contract-identity) 'after)
      (check-equal? (eq? (.get clone admission-contract) replacement) #t)
      ;; Storage compatibility does not certify a retargeted receipt.
      (check-equal? (poo-flow-validation-evidence? clone) #f)
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads (lambda () (.get evidence contract-identity))))
      (.put! original 'identity 'changed-after-read)
      (check-exception
        (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))))
