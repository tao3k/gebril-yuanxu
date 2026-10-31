;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         :std/test
        (only-in :clan/poo/object .def .o .ref)
        (only-in :clan/poo/mop element?)
        :yuanxu/poo-clos/interface)

(export poo-clos-method-bundle-test)

(def bundle-protocol (poo-clos-generic-protocol 'render))
(def other-protocol (poo-clos-generic-protocol 'other))

(def base-method
  (poo-clos-method
   'base (list (poo-clos-any-specializer))
   (lambda (_frame value) (list 'base value))))

(.defmethod-bundle render-methods bundle-protocol base-method)

(def (fresh-method identity tag)
  (poo-clos-method
   identity (list (poo-clos-any-specializer))
   (lambda (_frame value) (list tag value))))

(def (fresh-bundle identity protocol-value method-identity tag)
  (poo-clos-method-bundle
   identity protocol-value (list (fresh-method method-identity tag))))

(.def BundlePrototype.)
(.def (BundleChildPrototype. @ BundlePrototype.))
(.defclass BundleClass () ())

(def declared-protocol (poo-clos-generic-protocol 'declared-bundle))
(def protocol-evaluations 0)
(def target-evaluations 0)
(def body-evaluations 0)

(.defgeneric deferred-render (object)
  (protocol (begin
              (set! protocol-evaluations (+ protocol-evaluations 1))
              declared-protocol)))
(.defmethod (deferred-render object) 'fallback)
(def initial-generation
  (.ref (poo-clos-generic-binding-current deferred-render$poo-clos-generic)
        'generation))

(defrules native-deferred-method ()
  ((_ generic target body ...)
   (.defmethod (generic (object (prototype target))) body ...)))

(.defmethod-bundle declared-methods declared-protocol
  (.defmethod (deferred-render
                (object (prototype
                          (begin
                            (set! target-evaluations (+ target-evaluations 1))
                            BundlePrototype.))))
    (set! body-evaluations (+ body-evaluations 1))
    'base)
  (native-deferred-method deferred-render BundleChildPrototype.
    (list 'child (call-next-method) (next-method-p))))

(.defmethod-bundle empty-declared-methods declared-protocol)

(.defmethod-bundle wrong-declared-methods
  (poo-clos-generic-protocol 'declared-bundle)
  (native-deferred-method deferred-render BundleChildPrototype. 'wrong))

(.defgeneric deferred-kinds (object) (protocol declared-protocol))
(.defmethod (deferred-kinds object) 'fallback)
(.defmethod-bundle kind-methods declared-protocol
  (.defmethod (deferred-kinds (object BundleClass)) 'class)
  (.defmethod (deferred-kinds (object (eql 'sentinel))) 'eql)
  (native-deferred-method deferred-kinds BundlePrototype. 'prototype))

(.defgeneric deferred-strict (object &optional extra)
  (protocol declared-protocol))
(.defmethod-bundle incongruent-methods declared-protocol
  (.defmethod (deferred-strict object) 'wrong-arity))

(.defgeneric nested-registration (object))
(.defmethod (nested-registration object) 'before)
(.defgeneric deferred-body (object) (protocol declared-protocol))
(.defmethod-bundle body-methods declared-protocol
  (native-deferred-method deferred-body BundlePrototype.
    (.defmethod (nested-registration object) 'after)
    'outer))

;; Deferred descriptors need not resolve a Generic binding during declaration.
(.defmethod-bundle forward-methods declared-protocol
  (native-deferred-method forward-render BundlePrototype. 'forward))
(.defgeneric forward-render (object) (protocol declared-protocol))

(def poo-clos-method-bundle-test
  (test-suite "POO CLOS generic protocol and method bundle composition"
    (yuanxu-test-case "protocol expression preserves identity and evaluates once"
      (check-equal? protocol-evaluations 1)
      (check (eq? (.ref (poo-clos-generic-binding-current
                         deferred-render$poo-clos-generic) 'protocol)
                  declared-protocol) => #t))
    (yuanxu-test-case "direct and defrules methods remain inert until explicit composition"
      (check-equal? target-evaluations 1)
      (check-equal? body-evaluations 0)
      (check-equal? (length (.ref declared-methods 'methods)) 2)
      (check-equal? (.ref empty-declared-methods 'methods) '())
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-render$poo-clos-generic)
             'generation)
       initial-generation)
      (check-equal? (deferred-render (.o (:: @ BundleChildPrototype.))) 'fallback)
      (poo-clos-compose-method-bundle deferred-render$poo-clos-generic
                                    empty-declared-methods)
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-render$poo-clos-generic)
             'generation)
       initial-generation))
    (yuanxu-test-case "same-labelled different protocol rejects before registration"
      (check-exception
       (poo-clos-compose-method-bundle deferred-render$poo-clos-generic
                                      wrong-declared-methods)
       (lambda (failure)
         (and (poo-clos-failure? failure)
              (eq? (.ref failure 'code) 'method-bundle-protocol-mismatch))))
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-render$poo-clos-generic)
             'generation)
       initial-generation))
    (yuanxu-test-case "failed bundle construction cannot leak a declared method"
      (check-exception
       (let ()
         (.defmethod-bundle invalid-declared-methods declared-protocol
           (.defmethod (deferred-render object) 'leaked)
           #f)
         invalid-declared-methods)
       (lambda (failure)
         (and (poo-clos-failure? failure)
              (eq? (.ref failure 'code) 'invalid-method-bundle))))
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-render$poo-clos-generic)
             'generation)
       initial-generation)
      (check-equal? (deferred-render (.o (:: @ BundleChildPrototype.))) 'fallback))
    (yuanxu-test-case "explicit compose activates methods and lexical next-method"
      (poo-clos-compose-method-bundle deferred-render$poo-clos-generic
                                    declared-methods)
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-render$poo-clos-generic)
             'generation)
       (+ initial-generation 2))
      (check-equal? (deferred-render (.o (:: @ BundleChildPrototype.)))
                    '(child base #t))
      (check-equal? body-evaluations 1)
      (check-equal? target-evaluations 1)
      (check-equal? protocol-evaluations 1))
    (yuanxu-test-case "deferred class eql and prototype declarations share existing dispatch"
      (check-equal? (deferred-kinds 'sentinel) 'fallback)
      (poo-clos-compose-method-bundle deferred-kinds$poo-clos-generic kind-methods)
      (check-equal? (deferred-kinds 'sentinel) 'eql)
      (check-equal? (deferred-kinds (poo-clos-make-instance BundleClass)) 'class)
      (check-equal? (deferred-kinds (.o (:: @ BundleChildPrototype.))) 'prototype))
    (yuanxu-test-case "deferred congruence admission occurs at explicit composition"
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-strict$poo-clos-generic)
             'generation) 0)
      (check-exception
       (poo-clos-compose-method-bundle deferred-strict$poo-clos-generic
                                      incongruent-methods)
       (lambda (failure)
         (and (poo-clos-failure? failure)
              (eq? (.ref failure 'code) 'incongruent-method-lambda-list))))
      (check-equal?
       (.ref (poo-clos-generic-binding-current deferred-strict$poo-clos-generic)
             'generation) 0))
    (yuanxu-test-case "method body restores ordinary immediate nested declarations"
      (check-equal? (nested-registration 'value) 'before)
      (poo-clos-compose-method-bundle deferred-body$poo-clos-generic body-methods)
      (check-equal? (nested-registration 'value) 'before)
      (check-equal? (deferred-body (.o (:: @ BundlePrototype.))) 'outer)
      (check-equal? (nested-registration 'value) 'after))
    (yuanxu-test-case "deferred declarations may precede their Generic binding"
      (check-equal?
       (.ref (poo-clos-generic-binding-current forward-render$poo-clos-generic)
             'generation) 0)
      (poo-clos-compose-method-bundle forward-render$poo-clos-generic forward-methods)
      (check-equal? (forward-render (.o (:: @ BundleChildPrototype.))) 'forward))
    (yuanxu-test-case "thin defrule produces a native checked bundle"
      (check (element? ClosMethodBundle render-methods) => #t)
      (check (.ref render-methods 'protocol) => bundle-protocol)
      (check (.ref render-methods 'methods) => (list base-method)))
    (yuanxu-test-case "one protocol composes a bundle into generic dispatch"
      (let ((generic (poo-clos-generic-function 'render 1 protocol: bundle-protocol))
            (bundle (fresh-bundle 'base bundle-protocol 'base 'base)))
        (check (poo-clos-compose-method-bundle generic bundle) => generic)
        (check (poo-clos-call generic 'payload) => '(base payload))))
    (yuanxu-test-case "several bundles preserve ordinary replacement admission"
      (let* ((generic (poo-clos-generic-function 'render 1 protocol: bundle-protocol))
             (base-bundle (fresh-bundle 'base bundle-protocol 'base 'base))
             (replacement-bundle
              (fresh-bundle 'replacement bundle-protocol
                            'replacement 'replacement)))
        (check (poo-clos-compose-method-bundles
                generic (list base-bundle replacement-bundle))
               => generic)
        (check (poo-clos-call generic 'payload) => '(replacement payload))))
    (yuanxu-test-case "protocol identity mismatch fails before method ownership changes"
      (let* ((generic (poo-clos-generic-function 'render 1 protocol: bundle-protocol))
             (bundle (fresh-bundle 'wrong other-protocol 'wrong 'wrong)))
        (check-exception
         (poo-clos-compose-method-bundle generic bundle)
         (lambda (failure)
           (and (poo-clos-failure? failure)
                (eq? (.ref failure 'code)
                     'method-bundle-protocol-mismatch))))
        (check (poo-clos-generic-methods generic) => '())))))
