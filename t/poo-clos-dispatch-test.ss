;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; CLOS specializer, multi-dispatch, and standard-combination conformance.

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         (only-in :std/test
                 test-suite test-case check-equal? check-exception check)
        (only-in :clan/poo/object .o .ref .put! .all-slots object-slots $constant-slot-spec?
                 object-protocol-set! replay-slot-reads! object-read-issued?)
        (only-in :clan/poo/mop Type. element?)
        (only-in :clan/poo/slot-observation call-with-slot-read-observer
                 slot-read-key slot-read-receiver slot-read-dependencies)
        (only-in :yuanxu/poo-clos/objects make-effective-method make-invocation-frame
                 clos-call-carrier-policy-guard)
        (only-in :yuanxu/object-family/read-projection call-with-owned-read-projection owned-read-value!)
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot)
        :yuanxu/poo-clos/interface)

(export poo-clos-dispatch-test)

(def any-specializer (poo-clos-any-specializer))
(def animal-class (.o))
(def dog-class (.o (:: @ animal-class)))
(def cat-class (.o (:: @ animal-class)))
(def dog (.o (:: @ dog-class)))
(def cat (.o (:: @ cat-class)))

(def (failure-code? code)
  (lambda (error)
    (and (poo-clos-failure? error)
         (eq? (.ref error 'code) code))))

(def (primary-method identity specializers value)
  (poo-clos-method identity specializers
                   (lambda (_frame . _arguments) value)))

(def poo-clos-dispatch-test
  (test-suite "POO-native CLOS multi-dispatch conformance"
    (yuanxu-test-case "projection preserves multiple values and unwinds a failed region"
      (check-exception
        (call-with-owned-read-projection '() (lambda () #t)
          (lambda () (error "negative region failure"))) error?)
      (check-equal?
        (call-with-values
          (lambda ()
            (call-with-owned-read-projection '() (lambda () #t)
              (lambda () (values 'first 'second)))) list)
        '(first second)))
    (yuanxu-test-case "effective-method and native MOP hooks retain the complete call trace"
     (for-each
      (lambda (axis)
      (def exposed #f)
      (def body
        (lambda (frame _value)
          (when (eq? axis 'native-mop) (set! exposed frame)) 'done))
      (def protocol
        (poo-clos-generic-protocol 'open-projection
          compute-effective-method:
          (and (eq? axis 'effective)
               (lambda (_generic _args _methods original)
                 (set! exposed original) original))))
      (when (eq? axis 'native-mop) (object-protocol-set! protocol (.o)))
      (def generic
        (poo-clos-add-method
          (poo-clos-generic-function 'hooked-projection 1 protocol: protocol)
          (poo-clos-method 'check (list any-specializer) body)))
      (def result
        (.o answer:
          (call-with-owned-read-projection (list body) (clos-call-carrier-policy-guard)
            (cut poo-clos-call generic dog))))
      (def root #f)
      (call-with-slot-read-observer
        (lambda (read) (when (eq? (slot-read-key read) 'answer) (set! root read)))
        (lambda () (.ref result 'answer)))
      (def support (slot-read-dependencies root))
      ;; Internal bundle markers were removed. Preserve the stronger actual
      ;; contract: original issued records directly cover the escaped receiver.
      (check-equal? (andmap object-read-issued? support) #t)
      (check-equal? (ormap (lambda (read) (eq? (slot-read-receiver read) exposed))
                      support) #t)
      (.put! exposed 'negative-edit #t)
      (check-exception (replay-slot-reads! (list root) (lambda (_receiver _key) (void))) error?))
      '(effective native-mop)))
    (yuanxu-test-case "owned getter dependencies promote their external policy"
      ;; This isolated ownership fixture puts the only external read UNDER the
      ;; owned token, rather than relying on an independently observed root.
      (def policy (.o allowed: #t))
      (def result
        (.o answer:
          (call-with-owned-read-projection '() (lambda () #t)
            (lambda ()
              (def owned (owned-read-value! (.o value: (.ref policy 'allowed))))
              (.ref owned 'value)))))
      (def root #f)
      (call-with-slot-read-observer
        (lambda (read) (when (eq? (slot-read-key read) 'answer) (set! root read)))
        (lambda () (.ref result 'answer)))
      (yuanxu-debug-memory-snapshot 'owned-fixture-returned collect?: #t)
      (.put! policy 'allowed #f)
      (check-exception (replay-slot-reads! (list root) (lambda (_receiver _key) (void))) error?))
    (yuanxu-test-case "owned-read projection promotes external dependencies and preserves open frames"
      (check-equal? ((clos-call-carrier-policy-guard)) #t)
      (for-each
        (lambda (axis)
          (def policy (.o allowed: #t))
          (def value-checks 0)
          (def constraint
            (.o (:: @ Type.) .element?:
              (lambda (_value) (set! value-checks (+ 1 value-checks)) #t)))
          (def escaped #f)
          (def body
            (lambda (frame value)
              (when (memq axis '(open-frame known-frame)) (set! escaped frame))
              (and (.ref policy 'allowed) (element? constraint value))))
          (def generic
            (poo-clos-add-method (poo-clos-generic-function 'projected-reads 1)
              (poo-clos-method 'check (list any-specializer) body)))
          (def known (if (eq? axis 'open-frame) '() (list body)))
          (def result
            (.o answer:
              (call-with-owned-read-projection known (clos-call-carrier-policy-guard)
                (cut poo-clos-call generic dog))))
          (def root #f)
          (check-equal?
            (call-with-slot-read-observer
              (lambda (read) (when (eq? (slot-read-key read) 'answer) (set! root read)))
              (lambda () (.ref result 'answer))) #t)
          (replay-slot-reads! (list root) (lambda (_receiver _key) (void)))
          (check-equal? value-checks 1)
          (case axis
            ((policy) (.put! policy 'allowed #f))
            ((contract) (.put! constraint '.element? (lambda (_value) #f)))
            ((generic) (.put! generic 'generation (+ 1 (.ref generic 'generation))))
            ((open-frame known-frame) (.put! escaped 'qualifier 'before)))
          ;; Deliberately enroll an escaping fixture body as known: even this
          ;; producer-error probe may not turn a lost weak token into approval.
          (when (eq? axis 'known-frame)
            (yuanxu-debug-memory-snapshot 'invalidated-owned-frame collect?: #t))
          (check-exception
            (replay-slot-reads! (list root) (lambda (_receiver _key) (void))) error?))
        '(policy contract generic open-frame known-frame)))
    (yuanxu-test-case "prototype policy changes invalidate collected-carrier evidence"
      ;; Mutate the shared declaration LAST: restoring a value intentionally
      ;; does not restore its native revision or re-certify the old policy.
      (def body (lambda (_frame _value) 'done))
      (def generic
        (poo-clos-add-method (poo-clos-generic-function 'prototype-policy 1)
          (poo-clos-method 'check (list any-specializer) body)))
      (def projected
        (.o answer:
          (call-with-owned-read-projection (list body) (clos-call-carrier-policy-guard)
            (cut poo-clos-call generic dog))))
      (def prototype (.ref ClosInvocationFrame 'proto))
      (def original-kind (.ref prototype 'kind))
      (def projected-root #f)
      (call-with-slot-read-observer
        (lambda (read) (when (eq? (slot-read-key read) 'answer) (set! projected-root read)))
        (lambda () (.ref projected 'answer)))
      (yuanxu-debug-memory-snapshot 'projected-call-returned collect?: #t)
      (dynamic-wind
        (lambda () (.put! prototype 'kind 'negative-policy-injection))
        (lambda ()
          (check-exception
            (replay-slot-reads! (list projected-root) (lambda (_receiver _key) (void))) error?))
        (lambda () (.put! prototype 'kind original-kind)))
      (check-equal? ((clos-call-carrier-policy-guard)) #f))
    (yuanxu-test-case "completed CLOS reads retain policy Type Generic and escaped-frame dependencies"
      (for-each
        (lambda (axis)
          (def policy (.o allowed: #t))
          (def constraint (.o (:: @ Type.) .element?: (lambda (_value) #t)))
          (def escaped #f)
          (def generic
            (poo-clos-add-method
              (poo-clos-generic-function 'semantic-reads 1)
              (poo-clos-method 'check (list any-specializer)
                (lambda (frame value)
                  ;; A public method may retain its frame. Allocation identity
                  ;; or CLOS ancestry cannot certify a disposable dependency.
                  (set! escaped frame)
                  (and (.ref policy 'allowed) (element? constraint value))))))
          (def result (.o answer: (poo-clos-call generic dog)))
          (def reads (make-hash-table-eq))
          (check-equal?
            (call-with-slot-read-observer
              (lambda (read) (hash-put! reads read #t))
              (lambda () (.ref result 'answer))) #t)
          (replay-slot-reads! (hash-keys reads) (lambda (_receiver _key) (void)))
          ;; No source-byte change. Each is a real native object mutation,
          ;; after the lazy result has completed and its call stack returned.
          (case axis
            ((policy) (.put! policy 'allowed #f))
            ((contract) (.put! constraint '.element? (lambda (_value) #f)))
            ((generic) (.put! generic 'generation (+ 1 (.ref generic 'generation))))
            ((frame) (.put! escaped 'qualifier 'before)))
          (check-exception
            (replay-slot-reads! (hash-keys reads) (lambda (_receiver _key) (void)))
            error?))
        '(policy contract generic frame)))
    (yuanxu-test-case "CLOS carriers capture values without constructor-wide lazy closures"
      (def generic (poo-clos-generic-function 'carrier-values 1))
      (def method (primary-method 'carrier-method (list any-specializer) 'done))
      (def args (list dog))
      (def primaries (list method))
      (def effective (make-effective-method generic args '() '() primaries '()))
      ;; Independent original shape, not a constructor calling itself.
      (def generic-value generic)
      (def original
        (.o (:: @ (.ref ClosEffectiveMethod 'proto))
            generic: generic-value arguments: args around: '() before: '()
            primary: primaries after: '() groups: '() executor: #f))
      (check-equal? (.all-slots effective) (.all-slots original))
      (for-each (lambda (name)
                  (check-equal? (eq? (.ref effective name) (.ref original name)) #t))
        '(generic arguments primary executor))
      (check-equal? (andmap (lambda (entry) ($constant-slot-spec? (cdr entry)))
                      (object-slots effective)) #t)
      (def next (lambda (replacement) replacement))
      (def frame (make-invocation-frame effective args next 'primary method))
      (check-equal? (element? ClosInvocationFrame frame) #t)
      (check-equal? (eq? (.ref frame 'effective-method) effective) #t)
      (check-equal? (eq? (.ref frame 'arguments) args) #t)
      (check-equal? (eq? (.ref frame 'next) next) #t)
      (check-equal? (andmap (lambda (entry) ($constant-slot-spec? (cdr entry)))
                      (object-slots frame)) #t)
      (check-exception (make-effective-method generic 'invalid '() '() primaries '())
                       (failure-code? 'invalid-effective-method))
      (check-exception (make-invocation-frame effective args 42 'primary method)
                       (failure-code? 'invalid-invocation-frame)))
    (yuanxu-test-case "native prototype and any specializers participate in multi-argument dispatch"
      (let* ((generic (poo-clos-generic-function 'meet 2))
             (generic
              (poo-clos-add-method
               generic
               (primary-method
                'animal-animal
                (list (poo-clos-prototype-specializer animal-class)
                      (poo-clos-prototype-specializer animal-class))
                'animal-animal)))
             (generic
              (poo-clos-add-method
               generic
               (primary-method
                'dog-any
                (list (poo-clos-prototype-specializer dog-class) any-specializer)
                'dog-any)))
             (generic
              (poo-clos-add-method
               generic
               (primary-method
                'animal-cat
                (list (poo-clos-prototype-specializer animal-class)
                      (poo-clos-prototype-specializer cat-class))
                'animal-cat))))
        (check-equal? (poo-clos-call generic dog dog) 'dog-any)
        (check-equal? (poo-clos-call generic dog cat) 'dog-any)
        (let (second-first
              (poo-clos-generic-function
               'meet-second-first 2 argument-precedence-order: '(1 0)))
          (let loop ((methods (.ref generic 'methods)) (result second-first))
            (if (null? methods)
              (check-equal? (poo-clos-call result dog cat) 'animal-cat)
              (loop (cdr methods)
                    (let (method (car methods))
                      (poo-clos-add-method
                      result
                       (poo-clos-method
                        (.ref method 'identity) (.ref method 'specializers)
                        (.ref method 'body)
                        qualifier: (.ref method 'qualifier)
                        lambda-list: (.ref method 'lambda-list))))))))))

    (yuanxu-test-case "native prototypes cannot masquerade as CLOS classes"
      (check-exception
       (poo-clos-class-specializer animal-class)
       (failure-code? 'invalid-specializer)))

    (yuanxu-test-case "eql specializers are more specific than class specializers"
      (let* ((generic (poo-clos-generic-function 'feed 1))
             (generic
              (poo-clos-add-method
               generic
               (primary-method
                'dog (list (poo-clos-prototype-specializer dog-class)) 'dog)))
             (generic
              (poo-clos-add-method
               generic
               (primary-method
                'this-dog (list (poo-clos-eql-specializer dog)) 'this-dog))))
        (check-equal?
         (map (lambda (method) (.ref method 'identity))
              (poo-clos-compute-applicable-methods generic dog))
         '(this-dog dog))
        (check-equal? (poo-clos-call generic dog) 'this-dog)
        (check-equal? (poo-clos-call generic (.o (:: @ dog-class))) 'dog)))

    (yuanxu-test-case "standard qualifier order and lexical next are preserved"
      (let ((trace '())
            (base-generic (poo-clos-generic-function 'render 1)))
        (def (record value)
          (set! trace (append trace (list value))))
        (def (method identity specializer qualifier body)
          (poo-clos-method identity (list specializer) body
                           qualifier: qualifier))
        (def (around-dog frame _dog)
          (record 'around-dog-enter)
          (let (value (poo-clos-call-next-method frame))
            (record 'around-dog-exit)
            value))
        (def (before-animal _frame _animal) (record 'before-animal))
        (def (before-dog _frame _dog) (record 'before-dog))
        (def (primary-animal _frame _animal)
          (record 'primary-animal)
          'animal)
        (def (primary-dog frame replacement)
          (record 'primary-dog)
          (poo-clos-call-next-method frame replacement))
        (def (after-animal _frame _animal) (record 'after-animal))
        (def (after-dog _frame _dog) (record 'after-dog))
        (let* ((animal (poo-clos-prototype-specializer animal-class))
               (dog-specializer (poo-clos-prototype-specializer dog-class))
               (generic
                (foldl
                 (lambda (method generic)
                   (poo-clos-add-method generic method))
                 base-generic
                 (list
                  (method 'around-dog dog-specializer 'around around-dog)
                  (method 'before-animal animal 'before before-animal)
                  (method 'before-dog dog-specializer 'before before-dog)
                  (method 'primary-animal animal 'primary primary-animal)
                  (method 'primary-dog dog-specializer 'primary primary-dog)
                  (method 'after-animal animal 'after after-animal)
                  (method 'after-dog dog-specializer 'after after-dog)))))
          (check-equal? (poo-clos-call generic dog) 'animal)
          (check-equal?
           trace
           '(around-dog-enter before-dog before-animal
             primary-dog primary-animal after-animal after-dog
             around-dog-exit)))))

    (yuanxu-test-case "replacement arguments retain the exact applicable method set"
      (def (delegate frame _value)
        (poo-clos-call-next-method frame cat))
      (def (terminal _frame _value) 'terminal)
      (let* ((generic (poo-clos-generic-function 'replacement 1))
             (generic
              (poo-clos-add-method
               generic
               (poo-clos-method
                'animal (list (poo-clos-prototype-specializer animal-class))
                terminal)))
             (generic
              (poo-clos-add-method
               generic
               (poo-clos-method
                'dog (list (poo-clos-prototype-specializer dog-class))
                delegate))))
        (check-exception (poo-clos-call generic dog)
                         (failure-code? 'changed-applicable-methods))))

    (yuanxu-test-case "rest arguments and multiple values survive effective invocation"
      (def (many _frame _required . rest)
        (apply values rest))
      (let* ((generic (poo-clos-generic-function 'many 1 rest?: #t))
             (generic
              (poo-clos-add-method
               generic
               (poo-clos-method 'many (list any-specializer) many))))
        (check-equal?
         (call-with-values (lambda () (poo-clos-call generic 'x 1 2 3)) list)
         '(1 2 3))))

    (yuanxu-test-case "same qualifier and specializers replace the prior method"
      (let* ((generic (poo-clos-generic-function 'replace 1))
             (specializers (list any-specializer))
             (old (primary-method 'old specializers 'old))
             (new (primary-method 'new specializers 'new))
             (with-old (poo-clos-add-method generic old))
             (with-new (poo-clos-add-method with-old new)))
        (check (eq? generic with-old) => #t)
        (check (eq? with-old with-new) => #t)
        (check-equal? (poo-clos-call with-new 1) 'new)
        (check-equal? (.ref with-new 'generation) 2)
        (check-equal? (length (.ref with-new 'methods)) 1)
        (let (without-new (poo-clos-remove-method with-new new))
          (check-equal? (.ref without-new 'generation) 3)
          (check-equal? (.ref without-new 'methods) '())
          (check-exception (poo-clos-call without-new 1)
                           (failure-code? 'no-applicable-method)))))

    (yuanxu-test-case "a method has one generic owner and find-method uses ANSI qualifiers"
      (let* ((specializers (list any-specializer))
             (method (primary-method 'owned specializers 'owned))
             (first (poo-clos-generic-function 'first-owner 1))
             (second (poo-clos-generic-function 'second-owner 1)))
        (poo-clos-add-method first method)
        (check (eq? (poo-clos-method-generic-function method) first) => #t)
        (check-equal? (poo-clos-method-qualifiers method) '())
        (check (eq? (poo-clos-find-method first '() specializers) method) => #t)
        (check-equal?
         (poo-clos-find-method first '(before) specializers error?: #f) #f)
        (check-exception
         (poo-clos-add-method second method)
         (failure-code? 'method-owned-by-another-generic))
        (poo-clos-remove-method first method)
        (check-equal? (poo-clos-method-generic-function method) #f)
        (check (eq? (poo-clos-add-method second method) second) => #t)))

    (yuanxu-test-case "applicable methods extend keyword admission"
      (let* ((method-list
              (poo-clos-lambda-list 1 0 #f #t (list extra:) #f))
             (method
              (poo-clos-method
               'method-key (list any-specializer)
               (lambda (_frame _required . tail) tail)
               lambda-list: method-list))
             (generic
              (poo-clos-add-method
               (poo-clos-generic-function 'method-keys 1 rest?: #t)
               method)))
        (check-equal? (poo-clos-call generic 'value extra: 9)
                      (list extra: 9))
        (check-exception (poo-clos-call generic 'value unknown: 9)
                         (failure-code? 'invalid-keyword-argument))))

    (yuanxu-test-case "no-applicable-method precedes keyword validation"
      (let* ((protocol
              (poo-clos-generic-protocol
               'no-app-first
               no-applicable-method:
               (lambda (_generic _arguments) 'no-applicable)))
             (generic
              (poo-clos-generic-function
               'no-app-first 1 key?: #t keys: '(known)
               protocol: protocol)))
        (check-equal? (poo-clos-call generic 'value unknown: 1)
                      'no-applicable)))

    (yuanxu-test-case "terminal protocol functions are ordinary mutable generics"
      (let* ((target (poo-clos-generic-function 'terminal-target 1))
             (no-applicable
              (poo-clos-method
               'terminal-target/no-applicable
               (list (poo-clos-eql-specializer target))
               (lambda (_frame generic . arguments)
                 (list (.ref generic 'identity) arguments))
               lambda-list: (poo-clos-lambda-list 1 0 #t #f '() #f)))
             (terminal
              (poo-clos-method
               'terminal-target/primary (list any-specializer)
               (lambda (frame _value)
                 (poo-clos-call-next-method frame))))
             (no-next
              (poo-clos-method
               'terminal-target/no-next
               (list (poo-clos-eql-specializer target) any-specializer)
               (lambda (_frame generic method . arguments)
                 (list (.ref generic 'identity)
                       (.ref method 'identity) arguments))
               lambda-list: (poo-clos-lambda-list 2 0 #t #f '() #f))))
        (poo-clos-add-method poo-clos-no-applicable-method-generic
                             no-applicable)
        (check-equal? (poo-clos-call target 'absent)
                      '(terminal-target (absent)))
        (poo-clos-add-method target terminal)
        (poo-clos-add-method poo-clos-no-next-method-generic no-next)
        (check-equal? (poo-clos-call target 'present)
                      '(terminal-target terminal-target/primary (present)))
        (check (eq? (poo-clos-method-generic-function no-applicable)
                    poo-clos-no-applicable-method-generic) => #t)
        (poo-clos-remove-method poo-clos-no-applicable-method-generic
                                no-applicable)
        (poo-clos-remove-method poo-clos-no-next-method-generic no-next)))

    (yuanxu-test-case "typed failures close invalid and inapplicable calls"
      (check-exception
       (poo-clos-generic-function
        'bad-order 2 argument-precedence-order: '(0 0))
       (failure-code? 'invalid-argument-precedence-order))
      (let (generic (poo-clos-generic-function 'missing 1))
        (check-exception (poo-clos-call generic dog)
                         (failure-code? 'no-applicable-method))
        (check-exception (poo-clos-call generic)
                         (failure-code? 'argument-count-mismatch)))
      (let* ((generic (poo-clos-generic-function 'only-before 1))
             (method
              (poo-clos-method
               'before (list any-specializer)
               (lambda (_frame _value) (void)) qualifier: 'before)))
        (check-exception
         (poo-clos-call (poo-clos-add-method generic method) 1)
         (failure-code? 'no-primary-method)))
      (let* ((generic (poo-clos-generic-function 'no-next 1))
             (method
              (poo-clos-method
               'terminal (list any-specializer)
               (lambda (frame _value)
                 (poo-clos-call-next-method frame)))))
        (check-exception
         (poo-clos-call (poo-clos-add-method generic method) 1)
         (failure-code? 'no-next-method))))))
