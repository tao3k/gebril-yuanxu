;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declaration values, lexical bindings and POO inheritance need no filesystem.
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .def .o .get .slot? .put! .call .cc)
        (only-in :gerbil/expander core-expand datum->syntax)
        (rename-in (only-in :yuanxu/module-system/source/declaration .def) (.def publication-definition))
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-predicate-contract yuanxu-validation-evidence-accepted?)
        (only-in :clan/poo/object object?)
        (only-in :clan/poo/mop Type. Function TypeError?)
        (only-in :clan/poo/number Integer)
        (only-in :clan/poo/type Record)
        (only-in :yuanxu/module-system/source/publication ModulePublicationContract)
        (only-in :yuanxu/module-system/source/objects make-yuanxu-module-generated-source yuanxu-module-source-ref-value)
        (only-in :yuanxu/module-system/source/admission admit-module-publication!)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case))
(export module-declaration-value-test)
(def (exception-message thunk)
  (with-catch (lambda (exception)
                (call-with-output-string (lambda (port) (display-exception exception port))))
              (lambda () (thunk) "unexpected success")))
(def ScopeContract
  (yuanxu-predicate-contract 'test/publication-scope object? (lambda (_v _c) '())))
(def factory-calls 0)
(def dependencies 'author-value)

(def native-.ref 'author-shadow)
(publication-definition Published
  identity: 'custom/published
  core: (.o requires: (.o Provider: (.o module-id: 'core/provider contract: ScopeContract))
            scope-contract: ScopeContract label: 'parent
            exports: (begin (set! factory-calls (+ factory-calls 1))
                            (.o value: label provider: Provider author: dependencies
                                unused: (error "unused export must remain lazy"))))
  features: (.o unused: (error "unused feature must remain lazy")))

(def dependency-callback-calls 0)
(def provider-scope
  (.o run: (lambda (value) (set! dependency-callback-calls (+ dependency-callback-calls 1)) value)))
(def CheckedDependency
  (.cc YuanxuContract. identity: 'test/checked-dependency
    value-contract: (Record run: (list (Function (list Integer) (list Integer))))))
(publication-definition ProviderPublication
  identity: 'custom/provider
  core: (.o requires: (.o) scope-contract: ScopeContract exports: provider-scope)
  features: (.o))
(publication-definition ConsumerPublication
  identity: 'custom/consumer
  core: (.o requires: (.o Provider: (.o module-id: 'custom/provider contract: CheckedDependency))
            scope-contract: ScopeContract
            exports: (.o provider: Provider run: (lambda (value) (.call Provider run value))))
  features: (.o))

(def module-declaration-value-test
  (test-suite "In-memory Module declaration and POO behavior"
    (yuanxu-test-case "dependency bindings consume the checked Function before its callback"
      (set! dependency-callback-calls 0)
      (def view
        (yuanxu-load-modules
          (.o generation: "checked-dependency-test"
              module-ids: '(custom/provider custom/consumer)
              selected: '(custom/consumer) denied-modules: '()
              locate: make-yuanxu-module-generated-source
              current?: (lambda (_generation) #t)
              read-publication:
              (lambda (source)
                (if (eq? (yuanxu-module-source-ref-value source) 'custom/provider)
                  ProviderPublication ConsumerPublication)))))
      (def record (.call view .selected-record 'custom/consumer))
      (def scope (.get record scope))
      (check-exception (.call scope run "bad") TypeError?)
      (check-equal? dependency-callback-calls 0)
      (check-equal? (.call scope run 8) 8)
      (check-equal? dependency-callback-calls 1)
      (check-equal? (eq? (.get scope provider)
                        (.get record dependency-records Provider requirement-evidence candidate)) #t))
    (yuanxu-test-case "publication is deferred; native helpers and dependency identifiers are hygienic"
      (let* ((before factory-calls)
             (source (make-yuanxu-module-generated-source 'custom/published))
             (evidence (admit-module-publication! source 'custom/published Published (.o)))
             (provider (.o value: 'provider)))
        (check-equal? (yuanxu-validation-evidence-accepted? evidence) #t)
        (check-equal? factory-calls before)
        (check-equal? (.slot? (.get Published core) 'exports) #f)
        (let (scope ((.get Published core link) (.o Provider: provider)))
          (check-equal? factory-calls (+ before 1))
          (check-equal? (.get scope author) 'author-value)
          (check-equal? (.get scope value) 'parent)
          (check-equal? (eq? (.get scope provider) provider) #t))))
    (yuanxu-test-case "generated link wrappers consume only admitted dependency scopes"
      (let* ((before factory-calls)
             (AnyScope (yuanxu-predicate-contract 'test/any (lambda (_v) #t) (lambda (_v _c) '())))
             (provider (.o identity: 'core/provider features: (.o)
                           core: (.o requires: (.o) scope-contract: AnyScope link: (lambda (_deps) 42))))
             (view (yuanxu-load-modules
                    (.o generation: "publication-dependency-test" module-ids: '(core/provider custom/published)
                        selected: '(custom/published) denied-modules: '()
                        locate: make-yuanxu-module-generated-source
                        current?: (lambda (_generation) #t)
                        read-publication: (lambda (source)
                                            (if (eq? (yuanxu-module-source-ref-value source) 'core/provider)
                                              provider Published))))))
        (check-exception (.get view selected-records) error?)
        (check-equal? factory-calls before)))
    (yuanxu-test-case "cached parent link retains native effective outer-slot binding in child"
      (let (parent-link (.get Published core link))
        (.def (Child @ Published) core: =>.+ (.o label: 'child))
        (let (bindings (.o Provider: (.o)))
          (check-equal? (.get (parent-link bindings) value) 'parent)
          (check-equal? (.get ((.get Child core link) bindings) value) 'child)
          (check-equal? (.get (parent-link bindings) value) 'parent))))
    (yuanxu-test-case "duplicate fields, inherited dependencies and hand-written link wrappers are rejected"
      (for-each
       (lambda (example)
         (let (message
               (exception-message
                (lambda ()
                  (core-expand
                   (datum->syntax (quote-syntax publication-definition)
                     `(publication-definition Invalid identity: 'invalid core: ,(car example) features: (.o)))))))
           (check-equal? (if (string-contains message (cdr example)) #t #f) #t)))
       (list
        (cons '(.o requires: (.o) scope-contract: ScopeContract exports: (.o) exports: (.o)) "duplicate publication field")
        (cons '(.o requires: (.o (:: @ Published)) scope-contract: ScopeContract exports: (.o)) "without inherited aliases")
        (cons '(.o requires: (.o) scope-contract: ScopeContract exports: (.o) link: values) "core.link is generated"))))
    (yuanxu-test-case "Graph consumes the exact normalized publication from its single producer"
      ;; A generated-source capability exercises Graph admission directly;
      ;; the native file reader is outside this Case's boundary.
      (def publication
        (.o identity: 'custom/example features: (.o)
          core: (.o requires: (.o) scope-contract: ScopeContract
                    link: (lambda (_dependencies) (.o greeting: "original")))))
      (def view
        (yuanxu-load-modules
          (.o generation: "normalization-test" module-ids: '(custom/example)
              selected: '(custom/example) denied-modules: '()
              locate: make-yuanxu-module-generated-source
              current?: (lambda (_generation) #t)
              read-publication: (lambda (_source) publication))))
      (def original (.get ModulePublicationContract value-contract))
      (def checked #f)
      (def calls 0)
      (def ValueContract
        (.o (:: @ Type.)
          .element?: object?
          .validate:
          (lambda (value)
            (set! calls (+ calls 1))
            (set! checked
              (.o (:: @ value)
                core:
                (.o (:: @ (.get value core))
                  link: (lambda (_dependencies) (.o greeting: "normalized")))))
            checked)))
      ;; Test-only installation on the actual public Contract. The
      ;; producer remains unchanged and must normalize exactly once.
      (dynamic-wind
        (lambda () (.put! ModulePublicationContract 'value-contract ValueContract))
        (lambda ()
          (def record (.call view .selected-record 'custom/example))
          (check-equal? calls 1)
          (check-equal? (eq? (.get record publication) checked) #t)
          (check-equal? (eq? (.get record publication-evidence candidate) checked) #t)
          (check-equal? (.get record scope greeting) "normalized")
          (check-equal? (eq? record (.call view .selected-record 'custom/example)) #t)
          (check-equal? calls 1))
        (lambda () (.put! ModulePublicationContract 'value-contract original))))
    (yuanxu-test-case "normalized publication owner mismatch is refused before Graph insertion"
      ;; A generated-source capability exercises Graph admission directly;
      ;; the native file reader is outside this Case's boundary.
      (def publication
        (.o identity: 'custom/example features: (.o)
          core: (.o requires: (.o) scope-contract: ScopeContract
                    link: (lambda (_dependencies) (.o greeting: "original")))))
      (def view
        (yuanxu-load-modules
          (.o generation: "normalization-test" module-ids: '(custom/example)
              selected: '(custom/example) denied-modules: '()
              locate: make-yuanxu-module-generated-source
              current?: (lambda (_generation) #t)
              read-publication: (lambda (_source) publication))))
      (def original (.get ModulePublicationContract value-contract))
      (def ValueContract
        (.o (:: @ Type.)
          .element?: object?
          .validate: (lambda (value) (.o (:: @ value) identity: 'custom/wrong-owner))))
      (dynamic-wind
        (lambda () (.put! ModulePublicationContract 'value-contract ValueContract))
        (lambda ()
          (check-equal?
            (if (string-contains
                  (exception-message (lambda () (.get view selected-graph)))
                  "publication source owner mismatch") #t #f) #t))
        (lambda () (.put! ModulePublicationContract 'value-contract original))))))
