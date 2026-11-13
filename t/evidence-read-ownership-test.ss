;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads replay-slot-reads!
                 slot-read-key slot-read-receiver slot-read-dependencies call-with-slot-read-observer)
        (only-in :clan/poo/read-projection call-with-owned-read-projection
                 owned-read-copy! owned-read-derived! owned-read-leaf! owned-read-fields-present?
                 current-owned-read-open-guard)
        (only-in :clan/poo/prototype-map prototype-map)
        (only-in :clan/poo/validation-rebinding rebind-validation)
        (only-in :clan/poo/mop Slot Type. define-type validate object-read-issued?)
        (only-in :tao3k/yuanxu/module-system/types ModuleSourceRoleContract)
        (only-in :tao3k/yuanxu/module-system/authoring/roles TypesSourceRole.)
        (only-in :tao3k/yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        (only-in :tao3k/yuanxu/object-types/contracts yuanxu-classification-evidence yuanxu-validation-evidence
                 yuanxu-classification-evidence? yuanxu-validation-evidence?
                 YuanxuClassificationEvidence YuanxuValidationEvidence
                 YuanxuContract. yuanxu-contract-admit)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))
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
  (test-suite "Runtime evidence read ownership"
    (yuanxu-test-case "owned capture merges original roots without redelivering inherited observers"
      (def before (.o port: 5432))
      (def child (.o port: 5433))
      (def after (.o port: 5434))
      (for-each (lambda (receiver) (.get receiver port)) (list before child after))
      (def events '())
      (defvalues (_value reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-slot-read-observer
              (lambda (read)
                (when (eq? (slot-read-key read) 'port)
                  (set! events (cons (slot-read-receiver read) events))))
              (lambda ()
                (.get before port)
                (call-with-owned-read-projection '() (lambda () #t)
                  (lambda () (.get child port) (.get child port)))
                (.get after port))))))
      (check-equal? (reverse events) (list before child child after))
      (check-equal? (map slot-read-receiver
                      (filter (lambda (read) (eq? (slot-read-key read) 'port)) reads))
                    (list before child after))
      (check-equal? (original-read-graph? reads) #t)
      (replay-slot-reads! reads void))
    (yuanxu-test-case "owned capture failure retains issued partial support and original exception"
      (def child (.o port: 5432))
      (.get child port)
      (def failure (gensym 'owned-failure))
      (defvalues (caught reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (with-catch values
              (lambda ()
                (call-with-owned-read-projection '() (lambda () #t)
                  (lambda () (.get child port) (raise failure))))))))
      (check-equal? (eq? caught failure) #t)
      (check-equal? (original-read-graph? reads) #t)
      (check-equal? (map slot-read-receiver
                      (filter (lambda (read) (eq? (slot-read-key read) 'port)) reads))
                    (list child))
      (replay-slot-reads! reads void))
    (yuanxu-test-case "persistent declaration catalogs retain the open boundary without demanding descriptors"
      (for-each
        (lambda (policy)
          (def opened 0)
          (parameterize ((current-owned-read-open-guard (lambda () (set! opened (1+ opened)))))
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (owned-read-leaf! (make-object declarations: (prototype-map '() policy: policy)))
              (check-equal? opened 0)
              (def descriptor (.o .type: (error "declaration inspection forced a descriptor")))
              (owned-read-leaf! (make-object declarations:
                (prototype-map (list (cons 'port descriptor)) policy: policy)))
              (check-equal? opened 1)))
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def parent (make-object declarations:
                (prototype-map (list (cons 'port (.o))) policy: policy)))
              ;; A direct declaration must open the scope before a child or
              ;; descriptor is prepared. No snapshot list is used as a flag.
              (owned-read-derived! parent)
              (check-equal? opened 2)))))
        '(compact tree)))
    (yuanxu-test-case "fresh owned inventory keeps open and exposed query boundaries"
      (call-with-owned-read-projection '() (lambda () #t)
        (lambda ()
          (def candidate (owned-read-leaf!
            (.o port: 5432 unused: (error "inventory forced an unused value"))))
          (defvalues (present reads)
            (%call-with-recorded-slot-reads
              (lambda () (owned-read-fields-present? candidate '(port unused)))))
          (check-equal? present #t)
          (check-equal? (original-read-graph? reads) #t)
          (check-equal? (and (member '(names) (map slot-read-key reads)) #t) #t)
          (check-equal? (.ref/cached candidate 'unused) #f)
          ;; Public names are mutable. Once exposed, even a corrupted cache
          ;; cannot stand in for runtime presence on a subsequent check.
          (def names (.all-slots candidate))
          (set-car! names 'forged)
          (defvalues (again fallback)
            (%call-with-recorded-slot-reads
              (lambda () (owned-read-fields-present? candidate '(port)))))
          (check-equal? again #t)
          (check-equal? (and (member '(presence port) (map slot-read-key fallback)) #t) #t)
          (def other (owned-read-leaf!
            (.o port: 5433 unused: (error "presence forced an unused value"))))
          (def observed '())
          (call-with-slot-read-observer
            (lambda (read)
              (when (eq? (slot-read-receiver read) other)
                (set! observed (cons (slot-read-key read) observed))))
            (lambda () (check-equal? (owned-read-fields-present? other '(port unused)) #t)))
          (check-equal? (filter (lambda (key) (and (pair? key) (eq? (car key) 'presence)))
                              (reverse observed))
                        '((presence port) (presence unused)))
          (check-equal? (member '(names) observed) #f)
          (.put! other 'port 5440)
          (.put! other 'port 5433)
          (defvalues (restored restored-reads)
            (%call-with-recorded-slot-reads
              (lambda () (owned-read-fields-present? other '(port)))))
          (check-equal? restored #t)
          (check-equal? (and (member '(presence port) (map slot-read-key restored-reads)) #t) #t)
          (check-equal? (member '(names) (map slot-read-key restored-reads)) #f)
          (check-equal? (owned-read-fields-present? other '(missing)) #f))))
    (yuanxu-test-case "receipts retain actual candidate Contract Context and child identities"
      (def candidate (.o port: 443))
      (def context (.o generation: 'current))
      (def contract (.cc YuanxuContract. identity: 'actual-contract))
      (def diagnostics (list (.o kind: 'notice detail: 'retained)))
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
      ;; The ownership fixture must satisfy the actual Record boundaries.
      ;; Raw diagnostic lists and merely named objects are not valid evidence.
      (check-equal?
        (yuanxu-classification-evidence?
          (.cc classification diagnostics: (list '(notice retained)))) #f)
      (check-equal?
        (yuanxu-validation-evidence?
          (.cc evidence admission-contract: (.o identity: 'actual-contract))) #f)
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
      (yuanxu-debug-memory-snapshot 'runtime-validation-scratch-collected collect?: #t)
      (check-equal? (object? (hash-get witness 'checked)) #t)
      ;; Even an unread transitive parent field is part of the conservative
      ;; runtime parent-generation guard; mutation-and-restore cannot renew it.
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
    (yuanxu-test-case "runtime checked receiver with a MOP ancestor keeps full support"
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
    (yuanxu-test-case "normalized runtime checked receivers remain live original evidence"
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
    (yuanxu-test-case "late Contract name lookup keeps original identity and runtime invalidation"
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
        (replay-slot-reads! reads (lambda (_receiver _key) (void))) error?))
    (yuanxu-test-case "replaced evidence methods receive the receipt only after the open check"
      (def contract (.cc YuanxuContract. 'identity 'fixture))
      (def subject (.o port: 443))
      (def classification (yuanxu-classification-evidence 'fixture subject #t '() #f))
      (def validation (yuanxu-validation-evidence contract subject classification '() #t '() #f))
      (for-each
        (lambda (row)
          (def descriptor (car row))
          (def check (cadr row))
          (def receipt (caddr row))
          (def maintained (.ref descriptor '.element?))
          (def events '())
          (def (run boundary)
            (parameterize ((current-owned-read-open-guard boundary))
              (call-with-owned-read-projection '() void (cut check receipt))))
          (check-equal? (run (lambda () (error "maintained evidence method opened"))) #t)
          (dynamic-wind
            (lambda ()
              (.put! descriptor '.element?
                (lambda (value)
                  (check-equal? (eq? value receipt) #t)
                  (set! events (cons 'method events))
                  (maintained value))))
            (lambda ()
              (check-exception
                (run (lambda () (set! events (cons 'entry events)) (error "stale evidence entry")))
                error?)
              (check-equal? events '(entry))
              (set! events '())
              (check-equal? (run (lambda () (set! events (cons 'entry events)))) #t)
              (check-equal? (reverse events) '(entry method)))
            (lambda () (.put! descriptor '.element? maintained))))
        (list (list YuanxuClassificationEvidence yuanxu-classification-evidence? classification)
              (list YuanxuValidationEvidence yuanxu-validation-evidence? validation)
              ;; Standard Record Slot checking dispatches the classifier without
              ;; calling yuanxu-classification-evidence?.
              (list YuanxuClassificationEvidence
                    (lambda (_receipt) (yuanxu-validation-evidence? validation))
                    classification)))
      (def maintained-slot (.ref Slot '.slot.check))
      (def seen '())
      (dynamic-wind
        (lambda ()
          (.put! Slot '.slot.check
            (lambda (descriptor name value)
              (set! seen (cons value seen))
              (maintained-slot descriptor name value))))
        (lambda ()
          (for-each
            (lambda (check)
              (def entered? #f)
              (parameterize
                  ((current-owned-read-open-guard
                    (lambda () (set! entered? #t) (error "stale Slot check entry"))))
                (check-exception (call-with-owned-read-projection '() void check) error?))
              (check-equal? entered? #t)
              (check-equal? seen '()))
            (list (cut yuanxu-classification-evidence? classification)
                  (cut yuanxu-validation-evidence? validation))))
        (lambda () (.put! Slot '.slot.check maintained-slot))))))
