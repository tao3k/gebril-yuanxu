;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Hygienic CLOS declaration lowering and lambda-list conformance.

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         (only-in :std/test
                 test-suite test-case check-equal? check-exception check)
        (only-in :clan/poo/object .def .o .ref)
        (only-in :gerbil/expander datum->syntax)
        (only-in :gerbil/runtime/gambit
                 call-with-output-string display-exception
                 with-exception-catcher)
        (only-in :yuanxu/poo-clos/declaration-ir
                 parse-poo-clos-class-declaration-ir
                 parse-poo-clos-generic-declaration-ir
                 clos-lambda-declaration-ir-required
                 clos-parameter-declaration-ir-kind)
        (only-in :yuanxu/poo-clos/declaration-ir-core parse-clos-lambda-list)
        :yuanxu/poo-clos/interface)

(export poo-clos-syntax-test)

(def (failure-code? code)
  (lambda (error)
    (and (poo-clos-failure? error)
         (eq? (.ref error 'code) code))))

(def (syntax-error-message thunk)
  (with-exception-catcher
   (lambda (error)
     (call-with-output-string
      (lambda (port) (display-exception error port))))
   (lambda () (thunk) #f)))

(def (class-syntax-error slot-data . option-data)
  (let ((name (datum->syntax #f 'InvalidClass))
        (supers (datum->syntax #f '()))
        (slots (datum->syntax #f slot-data))
        (options (map (lambda (datum) (datum->syntax #f datum)) option-data)))
    (syntax-error-message
     (lambda ()
       (parse-poo-clos-class-declaration-ir
        name supers slots options name)))))

(def (generic-syntax-error lambda-list-data . option-data)
  (let ((name (datum->syntax #f 'invalid-generic))
        (lambda-list (datum->syntax #f lambda-list-data))
        (options (map (lambda (datum) (datum->syntax #f datum)) option-data)))
    (syntax-error-message
     (lambda ()
       (parse-poo-clos-generic-declaration-ir
        name lambda-list options name)))))

(def (method-specializer-syntax-error specializer)
  (syntax-error-message
   (lambda ()
     (parse-clos-lambda-list
      (datum->syntax #f (list (list 'value specializer))) #t))))

(.defgeneric entity-name (object))
(.defgeneric set-entity-name (new-value object))

(.defclass SyntaxEntity ()
  ((name (initarg name:)
         (initform 'unnamed)
         (accessor entity-name set-entity-name))))

(.defclass SyntaxPerson (SyntaxEntity)
  ((role (initarg role:) (initform 'user)))
  (default-initargs (name: 'default-person))
  (documentation "Syntax person class")
  (metaclass 'standard-class))

(.defgeneric describe-syntax
  (object &optional prefix &key ((punctuation: punctuation)))
  (argument-precedence-order object)
  (method-combination standard)
  (documentation "Describe syntax objects")
  (generic-function-class standard-generic-function)
  (method-class standard-method)
  (declare (optimize speed)))

(.defmethod (describe-syntax
  (object SyntaxEntity)
   &optional (prefix "entity" prefix-supplied?)
   &key ((punctuation: punctuation) "." punctuation-supplied?))
  (list prefix
        (entity-name object)
        punctuation
        prefix-supplied?
        punctuation-supplied?))

(.defmethod (describe-syntax
  (object SyntaxPerson)
   &optional (prefix "person" prefix-supplied?)
   &key ((punctuation: punctuation) "!" punctuation-supplied?)
   &aux (label 'person))
  (let (parent-result (call-next-method))
    (list label
          parent-result
          prefix
          punctuation
          prefix-supplied?
          punctuation-supplied?
          (next-method-p))))

(.defgeneric inline-described (object)
  (method ((object SyntaxEntity))
    (list 'inline (entity-name object))))

(.defclass StandardAccessorEntity ()
  ((value (initform 1) (accessor standard-value))))

(.defgeneric (setf explicit-name) (new-value object))
(.defmethod ((setf explicit-name) new-value (object SyntaxEntity))
  (poo-clos-set-slot-value! object 'name new-value))

(.def SyntaxPrototype.)
(.def (SyntaxChildPrototype. @ SyntaxPrototype.))
(.def SyntaxPeerPrototype.)

(.defgeneric describe-prototype (object))
(.defmethod (describe-prototype (object (prototype SyntaxPrototype.)))
  'base)
(.defmethod (describe-prototype (object (prototype SyntaxChildPrototype.)))
  (list 'child (call-next-method) (next-method-p)))

(.defgeneric inline-prototype (object)
  (method ((object (prototype SyntaxPrototype.)))
    'inline-prototype))

;; Private declaration frames must preserve the annotation's lexical binding.
(defrules prototype-method ()
  ((_ generic target result)
   (.defmethod (generic (object (prototype target))) result)))
(.defgeneric framed-prototype (object))
(let ((prototype (lambda (_target) SyntaxEntity)))
  (prototype-method framed-prototype SyntaxPrototype. 'framed-prototype))

(.defgeneric prototype-crossing (left right))
(.defmethod (prototype-crossing left right) 'fallback)
(.defmethod (prototype-crossing
             (left (prototype SyntaxPrototype.))
             (right (prototype SyntaxPeerPrototype.)))
  'crossed)

(.defgeneric mixed-specializers (object))
(.defmethod (mixed-specializers (object SyntaxEntity)) 'class)
(.defmethod (mixed-specializers (object (prototype SyntaxPrototype.))) 'prototype)
(.defmethod (mixed-specializers (object (eql 'sentinel))) 'eql)

;; A lexical binding with the same spelling is an ordinary class expression.
(.defgeneric shadowed-prototype-marker (object))
(let ((prototype (lambda (_target) SyntaxEntity)))
  (.defmethod (shadowed-prototype-marker
                (object (prototype SyntaxPrototype.)))
    'shadowed-class))

(def prototype-target-evaluations 0)
(.defgeneric prototype-expression (object))
(.defmethod (prototype-expression
              (object (prototype
                        (begin
                          (set! prototype-target-evaluations
                                (+ prototype-target-evaluations 1))
                          SyntaxPrototype.))))
  'prototype-expression)

(def syntax-protocol (poo-clos-generic-protocol 'syntax-inline))
(.defgeneric protocol-inline (object)
  (protocol syntax-protocol)
  (method ((object (prototype SyntaxPrototype.))) 'protocol-inline))

(def poo-clos-syntax-test
  (test-suite "hygienic POO-native CLOS declarations"
    (yuanxu-test-case "generic protocol identity reaches inline method admission"
      (check (eq? (.ref (poo-clos-generic-binding-current
                         protocol-inline$poo-clos-generic) 'protocol)
                  syntax-protocol) => #t)
      (check-equal? (protocol-inline (.o (:: @ SyntaxChildPrototype.)))
                    'protocol-inline))
    (yuanxu-test-case "protocol clauses reject duplicates and malformed arity"
      (check
       (integer?
        (string-contains
         (generic-syntax-error '(value) '(protocol first) '(protocol second))
         "poo-clos-duplicate-generic-option"))
       => #t)
      (for-each
       (lambda (option)
         (check
          (integer?
           (string-contains (generic-syntax-error '(value) option)
                            "poo-clos-invalid-generic-option"))
          => #t))
       '((protocol) (protocol first second) (protocol . improper))))
    (yuanxu-test-case "prototype declarations preserve native ancestry and next methods"
      (check-equal? (describe-prototype (.o (:: @ SyntaxPrototype.))) 'base)
      (check-equal? (describe-prototype (.o (:: @ SyntaxChildPrototype.)))
                    '(child base #t))
      (check-equal? (inline-prototype (.o (:: @ SyntaxChildPrototype.)))
                    'inline-prototype)
      (check-equal?
       (map (lambda (method)
              (.ref (car (.ref method 'specializers)) 'kind))
            (.ref (poo-clos-generic-binding-current
                   describe-prototype$poo-clos-generic) 'methods))
       '(prototype prototype)))

    (yuanxu-test-case "prototype declarations dispatch across independently inherited axes"
      (let ((left (.o (:: @ SyntaxChildPrototype.)))
            (right (.o (:: @ SyntaxPeerPrototype.))))
        (check-equal? (prototype-crossing left right) 'crossed)
        (check-equal? (prototype-crossing right left) 'fallback)
        (check-equal? (prototype-crossing left (.o)) 'fallback)))

    (yuanxu-test-case "private defrules frames preserve native prototype annotation hygiene"
      (check-equal? (framed-prototype (.o (:: @ SyntaxChildPrototype.)))
                    'framed-prototype)
      (let* ((generic (poo-clos-generic-binding-current
                       framed-prototype$poo-clos-generic))
             (method (car (.ref generic 'methods)))
             (specializer (car (.ref method 'specializers))))
        (check-equal? (.ref specializer 'kind) 'prototype)))

    (yuanxu-test-case "class eql and prototype declarations retain distinct specializers"
      (check-equal? (mixed-specializers (poo-clos-make-instance SyntaxEntity)) 'class)
      (check-equal? (mixed-specializers (.o (:: @ SyntaxChildPrototype.))) 'prototype)
      (check-equal? (mixed-specializers 'sentinel) 'eql)
      (check-equal? (shadowed-prototype-marker
                     (poo-clos-make-instance SyntaxEntity))
                    'shadowed-class)
      (check-equal?
       (clos-parameter-declaration-ir-kind
        (car (clos-lambda-declaration-ir-required
              (parse-clos-lambda-list
               (datum->syntax #f '((value (prototype SyntaxPrototype.)))) #t))))
       'prototype))

    (yuanxu-test-case "prototype targets are expressions evaluated at method admission"
      (check-equal? prototype-target-evaluations 1)
      (check-equal? (prototype-expression (.o (:: @ SyntaxChildPrototype.)))
                    'prototype-expression)
      (check-equal? (prototype-expression (.o (:: @ SyntaxPrototype.)))
                    'prototype-expression)
      (check-equal? prototype-target-evaluations 1)
      (let (generation
            (.ref (poo-clos-generic-binding-current
                   prototype-expression$poo-clos-generic) 'generation))
        (check-exception
         (.defmethod (prototype-expression (object (prototype #f))) 'invalid)
         (failure-code? 'invalid-specializer))
        (check-exception
         (.defmethod (prototype-expression (object SyntaxPrototype.)) 'invalid-class)
         (failure-code? 'invalid-specializer))
        (check-equal?
         (.ref (poo-clos-generic-binding-current
                prototype-expression$poo-clos-generic) 'generation)
         generation)))

    (yuanxu-test-case "malformed prototype and eql annotations fail during parsing"
      (for-each
       (lambda (specializer)
         (check
          (integer?
           (string-contains (method-specializer-syntax-error specializer)
                            "poo-clos-invalid-specializer"))
          => #t))
       '((prototype) (prototype First Second) (prototype . Target)
         (eql) (eql First Second))))

    (yuanxu-test-case "defclass lowers slots, defaults, and accessor methods"
      (let (person (poo-clos-make-instance SyntaxPerson role: 'admin))
        (check (poo-clos-instance? person) => #t)
        (check-equal? (entity-name person) 'default-person)
        (check-equal? (poo-clos-slot-value person 'role) 'admin)
        (check-equal? (poo-clos-class-documentation SyntaxPerson)
                      "Syntax person class")
        (check-equal? (poo-clos-class-metaclass SyntaxPerson) 'standard-class)
        (check-equal? (set-entity-name 'renamed person) 'renamed)
        (check-equal? (entity-name person) 'renamed)))

    (yuanxu-test-case "defmethod binds optional, key, supplied-p, aux, and lexical next"
      (let (person (poo-clos-make-instance SyntaxPerson name: 'Ada))
        (check-equal?
         (describe-syntax person)
         '(person ("entity" Ada "." #f #f) "person" "!" #f #f #t))
        (check-equal?
         (describe-syntax person "Dr" punctuation: "?")
         '(person ("Dr" Ada "?" #t #t) "Dr" "?" #t #t #t))))

    (yuanxu-test-case "defgeneric installs inline methods"
      (let (entity (poo-clos-make-instance SyntaxEntity name: 'inline-name))
        (check-equal? (inline-described entity) '(inline inline-name))))

    (yuanxu-test-case "one-name accessors install ANSI reader and SETF writer"
      (let (entity (poo-clos-make-instance StandardAccessorEntity))
        (check-equal? (standard-value entity) 1)
        (check-equal? (poo-clos-setf 'standard-value 2 entity) 2)
        (check-equal? (standard-value entity) 2)
        (check
         (if (poo-clos-find-generic-function
              '(setf standard-value) error?: #f) #t #f)
         => #t)
        (check
         (if (poo-clos-find-generic-function
              (list 'setf 'standard-value) error?: #f) #t #f)
         => #t)))

    (yuanxu-test-case "SETF function names are valid generic declarations"
      (let (entity (poo-clos-make-instance SyntaxEntity name: 'before))
        (check-equal? (poo-clos-setf 'explicit-name 'after entity) 'after)
        (check-equal? (entity-name entity) 'after)))

    (yuanxu-test-case "generic binding preserves identity across generations"
      (check-equal?
       (.ref (poo-clos-generic-binding-current
              describe-syntax$poo-clos-generic)
             'generation)
       2)
      (check-equal?
       (length
        (.ref (poo-clos-generic-binding-current
               describe-syntax$poo-clos-generic)
              'methods))
       2)
      (check-equal? (poo-clos-generic-documentation
                     describe-syntax$poo-clos-generic)
                    "Describe syntax objects")
      (check-equal? (poo-clos-generic-function-class
                     describe-syntax$poo-clos-generic)
                    'standard-generic-function)
      (check-equal? (poo-clos-generic-method-class
                     describe-syntax$poo-clos-generic)
                    'standard-method))

    (yuanxu-test-case "with-slots and with-accessors are live mutable places"
      (let ((person (poo-clos-make-instance SyntaxPerson name: 'first))
            (standard (poo-clos-make-instance StandardAccessorEntity)))
        (check-equal?
         (.with-slots (name (role-value role)) person
           (let (before name)
             (set! name 'second)
             (set! role-value 'admin)
             (list before name role-value)))
         '(first second admin))
        (check-equal?
         (.with-accessors ((observed entity-name)) person
           (let (before observed)
             (set-entity-name 'third person)
             (list before observed)))
         '(second third))
        (check-equal?
         (.with-accessors ((observed standard-value)) standard
           (let (before observed)
             (set! observed 9)
             (list before observed)))
         '(1 9))
        (check-equal? (standard-value standard) 9)))

    (yuanxu-test-case "runtime congruence rejects a method before binding mutation"
      (let* ((binding
              (poo-clos-generic-binding
               'strict
               (poo-clos-generic-function 'strict 1 optional: 1)))
             (generation
              (.ref (poo-clos-generic-binding-current binding) 'generation))
             (method
              (poo-clos-method
               'strict (list (poo-clos-any-specializer))
               (lambda (_frame _required) 'bad)
               lambda-list:
               (poo-clos-lambda-list 1 0 #f #f '() #f))))
        (check-exception
         (poo-clos-generic-binding-add-method! binding method)
         (failure-code? 'incongruent-method-lambda-list))
        (check-equal?
         (.ref (poo-clos-generic-binding-current binding) 'generation)
         generation)))

    (yuanxu-test-case "unknown keyword calls fail before method execution"
      (let (person (poo-clos-make-instance SyntaxPerson name: 'Ada))
        (check-exception
         (describe-syntax person "Dr" unknown: 1)
         (failure-code? 'invalid-keyword-argument))
        (check-exception
         (describe-syntax person "Dr" unknown: 1 allow-other-keys: #f)
         (failure-code? 'invalid-keyword-argument))
        (check-equal?
         (describe-syntax person "Dr" unknown: 1 allow-other-keys: #t)
         '(person ("Dr" Ada "." #t #f) "Dr" "!" #t #f #t))))

    (yuanxu-test-case "declaration IR rejects duplicates, unknown clauses, and bad order"
      (check
       (integer?
        (string-contains
         (class-syntax-error '((slot) (slot)))
         "poo-clos-duplicate-slot"))
       => #t)
      (check
       (integer?
        (string-contains
         (class-syntax-error '((slot (mystery value))))
         "poo-clos-unknown-slot-option"))
       => #t)
      (check
       (integer?
        (string-contains
         (generic-syntax-error '(value &key key &optional late))
         "poo-clos-invalid-lambda-list-order"))
       => #t)
      (check
       (integer?
        (string-contains
         (generic-syntax-error '(value value))
         "poo-clos-duplicate-lambda-variable"))
       => #t))))
