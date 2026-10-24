;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Same native composition as the pinned contract/function service examples.
(import :std/test
        (only-in :std/error Error?)
        :clan/poo/object
        (only-in :clan/poo/mop Function element? validate TypeError?)
        (only-in :clan/poo/number Integer)
        (only-in :clan/poo/type Record)
        (only-in :clan/poo/object-contract-flow checked-action)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        :yuanxu/module-system/schema/slot-contracts
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-contract-admit
                 yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/ops/func validate-script preview-script)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export contract-function-composition-test)

(def Callback (Function (list Integer) (list Integer)))
;; Upstream literal declaration is the independent construction control.
(def LiteralCallbacks (Record run: (list Callback) retry: (list Callback optional: #t)))

(def CallbackSlot
  (yuanxu-contract-slot 'callback/run 'run Callback #t '()))
(def OptionalSlot
  (yuanxu-contract-slot 'callback/retry 'retry Callback #f '()))
(def Callbacks
  (yuanxu-object-contract 'callbacks 'test 'Callbacks object?
    (list CallbackSlot OptionalSlot) '()))

(def contract-function-composition-test
  (test-suite "native Contract Function and FUN composition"
    (yuanxu-test-case "slot validation retains the Function wrapper"
      (def checked (yuanxu-contract-check-slot! CallbackSlot identity))
      (check-equal? (checked 3) 3)
      (check-exception (checked "bad argument") TypeError?)
      (def bad (yuanxu-contract-check-slot! CallbackSlot (lambda (_) "bad result")))
      (check-exception (bad 3) TypeError?))
    (yuanxu-test-case "Record owns required optional and inherited fields"
      (check-equal? (element? Callbacks (.o)) #f)
      (check-equal? (element? Callbacks (.o run: identity retry: 7)) #f)
      (def parent (.o run: identity audit: 'retained))
      (def checked (validate Callbacks parent))
      (check-equal? (.slot? checked 'retry) #f)
      (check-equal? (.get checked audit) 'retained)
      (check-exception ((.get checked run) "bad") TypeError?)
      (def child (.cc parent retry: (lambda (_) "bad result")))
      (check-exception ((.get (validate Callbacks child) retry) 3) TypeError?)
      (check-equal? (.slot? parent 'retry) #f))
    (yuanxu-test-case "native child Slot refinements also update projected type facts"
      (.get Callbacks effective-slots)
      (def child
        (.cc Callbacks slots:
          (.cc (.get Callbacks slots) run:
            (.cc (.get Callbacks slots run) type: Integer optional: #t))))
      (def projected (car (yuanxu-object-contract-slots child)))
      (check-equal? (eq? (yuanxu-contract-slot-type projected) Integer) #t)
      (check-equal? (yuanxu-contract-slot-required? projected) #f)
      (check-equal? (element? child (.o)) #t)
      (check-equal? (element? child (.o run: 3)) #t)
      (check-equal? (element? child (.o run: identity)) #f)
      (check-equal? (element? LiteralCallbacks (.o run: identity)) #t)
      (check-equal? (element? Callbacks (.o)) #f)
      (check-exception
        (yuanxu-object-contract-slots
          (.cc Callbacks slot-schemas: (list CallbackSlot CallbackSlot))) Error?))
    (yuanxu-test-case "Function retains defaults keywords multiple results and returned callbacks"
      (def signature
        (Function (list Integer Callback) (list Integer)
          optional: (list Integer) keywords: (list (cons scale: Integer))))
      (def checked
        (yuanxu-contract-check-slot!
          (yuanxu-contract-slot 'service/run 'run signature #t '())
          (lambda (value (bonus 2) scale: (scale 3))
            (values (* scale (+ value bonus)) (lambda (_) "bad result")))))
      (defvalues (answer callback) (checked 1))
      (check-equal? answer 9)
      (check-exception (callback 1) TypeError?)
      (defvalues (custom _callback) (checked 1 4 scale: 2))
      (check-equal? custom 10)
      (check-exception (checked 1 scale: "bad") TypeError?))
    (yuanxu-test-case "Core value admission normalizes once before contextual obligations"
      (def wraps 0)
      (def counted
        (.o inherit: (list Callback)
          (.validate (inherited)
            (lambda (candidate)
              (set! wraps (+ wraps 1))
              ((inherited) candidate)))))
      (def shape
        (yuanxu-object-contract 'counted 'test 'Counted object?
          (list (yuanxu-contract-slot 'counted/run 'run counted #t '())) '()))
      (def seen #f)
      (def Contract
        (.cc YuanxuContract. identity: 'counted value-contract: shape
          .obligations: (lambda (candidate _context) (set! seen candidate) '())))
      (def original (.o run: identity))
      (def evidence (yuanxu-contract-admit Contract original #f))
      (check-equal? wraps 1)
      (check-equal? (eq? seen (.get evidence candidate)) #t)
      (check-exception ((.get seen run) "bad") TypeError?)
      (check-equal? ((.get original run) "untouched") "untouched"))
    (yuanxu-test-case "Ops consumes checked progress factories and their returned callbacks"
      (def calls 0)
      (def script
        (.o command: '("true") directory: #f environment: (.o)
            timeout: #f log: #f check-status: #t
            progress: (lambda () (set! calls (+ 1 calls)) identity)))
      (def prepared (preview-script script))
      (check-equal? calls 0)
      (def reader ((.get prepared progress)))
      (check-equal? calls 1)
      (check-equal? (reader "line") "line")
      (check-exception (reader 7) TypeError?)
      (check-equal? (((.get script progress)) 7) 7)
      (def bad (.cc script progress: (lambda () 7)))
      (check-exception ((.get (preview-script bad) progress)) TypeError?)
      (check-exception (validate-script (.cc script command: '(7))) TypeError?))
    (yuanxu-test-case "FUN passes the normalized subject into Core evidence and exact publication"
      (def context (.o generation: 'current))
      (def Contract (.cc YuanxuContract. identity: 'callbacks))
      (def invocation
        (metadata.contract (metadata.predicate "subject" object?)
          (metadata.predicate "accepted evidence" yuanxu-validation-evidence-accepted?)
          (lambda _ #t) metadata.truth))
      (def (view evidence)
        (.o subject: (.get evidence candidate) descriptor: (.get evidence admission-contract)
            context: (.get evidence context)))
      (def consume-count 0)
      (def action
        (checked-action Callbacks
          (lambda (checked)
            (set! consume-count (+ consume-count 1))
            (def evidence (yuanxu-contract-admit Contract checked context))
            ;; Bind the exact normalized subject produced by this admission.
            (def subject (.get evidence candidate))
            (metadata.publish (metadata.bind-evidence invocation subject Contract context view)
              context (lambda (_) (values evidence subject)) subject))))
      (defvalues (evidence next failure) (action (.o run: identity)))
      (check-equal? failure #f)
      (check-equal? (eq? next (.get evidence candidate)) #t)
      (check-exception ((.get next run) "bad") TypeError?)
      (check-exception (action (.o run: 7)) TypeError?)
      (check-equal? consume-count 1)
      (def other (.o generation: 'other))
      (defvalues (rejected retained refusal)
        (metadata.publish (metadata.bind-evidence invocation next Contract other view)
          context (lambda (_) (values evidence other)) next))
      (check-equal? rejected #f)
      (check-equal? (eq? retained context) #t)
      (check-equal? (metadata.failure-phase refusal) 'logic))))
