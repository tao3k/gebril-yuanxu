;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declaration values, lexical bindings and POO inheritance need no filesystem.
(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .def .o .get .slot? .put! .call .cc)
        (only-in :gerbil/expander core-expand datum->syntax)
        (rename-in (only-in :tao3k/yuanxu/module-system/source/declaration .def) (.def publication-definition))
        (only-in :tao3k/yuanxu/object-types/contracts yuanxu-validation-evidence-accepted?)
        (only-in :clan/poo/object object?)
        (only-in :clan/poo/mop Type. Function TypeError?)
        (only-in :clan/poo/number Integer)
        (only-in :clan/poo/type Record)
        (only-in :tao3k/yuanxu/module-system/source/publication ModulePublicationContract)
        (only-in :tao3k/yuanxu/module-system/source/objects make-yuanxu-module-generated-source yuanxu-module-source-ref-value
                 yuanxu-module-source-ref-prototype yuanxu-module-source-ref-construction-current?)
        (only-in :tao3k/yuanxu/module-system/source/admission admit-module-publication!)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case))
(export module-declaration-value-test)
(def (exception-message thunk)
  (with-catch (lambda (exception)
                (call-with-output-string (lambda (port) (display-exception exception port))))
              (lambda () (thunk) "unexpected success")))
(def ScopeContract
  (.cc Type. identity: 'test/publication-scope .element?: object?))
(def factory-calls 0)
(def dependencies 'author-value)

(def runtime-.ref 'author-shadow)
(publication-definition Published
  identity: 'custom/published
  core: (.o scope-contract: ScopeContract label: 'parent
            exports: (begin (set! factory-calls (+ factory-calls 1))
                            (.o value: label provider: dependencies author: dependencies
                                unused: (error "unused export must remain lazy"))))
  features: (.o unused: (error "unused feature must remain lazy")))

(def dependency-callback-calls 0)
(def provider-scope
  (.o run: (lambda (value) (set! dependency-callback-calls (+ dependency-callback-calls 1)) value)))
(def CheckedDependency
  (.cc (Record run: (list (Function (list Integer) (list Integer))))
    identity: 'test/checked-dependency))
(publication-definition ProviderPublication
  identity: 'custom/provider
  core: (.o scope-contract: ScopeContract exports: provider-scope)
  features: (.o))
(publication-definition ConsumerPublication
  identity: 'custom/consumer
  core: (.o scope-contract: ScopeContract
            exports: (let (provider (.call CheckedDependency .validate provider-scope))
                       (.o provider: provider run: (lambda (value) (.call provider run value)))))
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
      (check-equal? (eq? (.get scope provider) (.get record scope provider)) #t))
    (yuanxu-test-case "publication is deferred; runtime helpers and dependency identifiers are hygienic"
      (let* ((before factory-calls)
             (source (make-yuanxu-module-generated-source 'custom/published))
             (evidence (admit-module-publication! source 'custom/published Published (.o)))
             (provider (.o value: 'provider)))
        (check-equal? (yuanxu-validation-evidence-accepted? evidence) #t)
        (check-equal? factory-calls before)
        (check-equal? (.slot? (.get Published core) 'exports) #t)
        (let (scope (.get Published core exports))
          (check-equal? factory-calls (+ before 1))
          (check-equal? (.get scope author) 'author-value)
          (check-equal? (.get scope value) 'parent)
          (check-equal? (eq? (.get scope provider) dependencies) #t))))
    (yuanxu-test-case "parent and child retain their effective outer-slot bindings"
      (.def (Child @ Published) core: =>.+ (.o label: 'child))
      (check-equal? (.get Published core exports value) 'parent)
      (check-equal? (.get Child core exports value) 'child)
      (check-equal? (.get Published core exports value) 'parent))
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
        (cons '(.o requires: (.o (:: @ Published)) scope-contract: ScopeContract exports: (.o)) "Module core uses Gerbil imports")
        (cons '(.o requires: (.o) scope-contract: ScopeContract exports: (.o) link: values) "Module core uses Gerbil imports"))))
    (yuanxu-test-case "Graph consumes the exact normalized publication from its single producer"
      ;; A generated-source capability exercises Graph admission directly;
      ;; the runtime file reader is outside this Case's boundary.
      (def publication
        (.o identity: 'custom/example features: (.o)
          core: (.o scope-contract: ScopeContract
                    exports: (.o greeting: "original"))))
      (def view
        (yuanxu-load-modules
          (.o generation: "normalization-test" module-ids: '(custom/example)
              selected: '(custom/example) denied-modules: '()
              locate: make-yuanxu-module-generated-source
              current?: (lambda (_generation) #t)
              read-publication: (lambda (_source) publication))))
      (def original (.get ModulePublicationContract .validate))
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
                  exports: (.o greeting: "normalized"))))
            checked)))
      ;; Test-only installation on the actual public Contract. The
      ;; producer remains unchanged and must normalize exactly once.
      (dynamic-wind
        (lambda () (.put! ModulePublicationContract '.validate (.get ValueContract .validate)))
        (lambda ()
          (def record (.call view .selected-record 'custom/example))
          (check-equal? calls 1)
          (check-equal? (eq? (.get record publication) checked) #t)
          (check-equal? (eq? (.get record publication-evidence candidate) checked) #t)
          (check-equal? (.get record scope greeting) "normalized")
          (check-equal? (eq? record (.call view .selected-record 'custom/example)) #t)
          (check-equal? calls 1))
        (lambda () (.put! ModulePublicationContract '.validate original))))
    (yuanxu-test-case "normalized publication owner mismatch is refused before Graph insertion"
      ;; A generated-source capability exercises Graph admission directly;
      ;; the runtime file reader is outside this Case's boundary.
      (def publication
        (.o identity: 'custom/example features: (.o)
          core: (.o scope-contract: ScopeContract
                    exports: (.o greeting: "original"))))
      (def view
        (yuanxu-load-modules
          (.o generation: "normalization-test" module-ids: '(custom/example)
              selected: '(custom/example) denied-modules: '()
              locate: make-yuanxu-module-generated-source
              current?: (lambda (_generation) #t)
              read-publication: (lambda (_source) publication))))
      (def original (.get ModulePublicationContract .validate))
      (def ValueContract
        (.o (:: @ Type.)
          .element?: object?
          .validate: (lambda (value) (.o (:: @ value) identity: 'custom/wrong-owner))))
      (dynamic-wind
        (lambda () (.put! ModulePublicationContract '.validate (.get ValueContract .validate)))
        (lambda ()
          (check-equal?
            (if (string-contains
                  (exception-message (lambda () (.get view selected-graph)))
                  "publication source owner mismatch") #t #f) #t))
        (lambda () (.put! ModulePublicationContract '.validate original))))
    ;; Keep last: restoring the Slot value does not undo its runtime revision.
    (yuanxu-test-case "the source constructor prototype is part of closed-prefix support"
      (check-equal? (yuanxu-module-source-ref-construction-current?) #t)
      (dynamic-wind
        (lambda () (.put! yuanxu-module-source-ref-prototype 'prefix-test-marker #t))
        (lambda () (check-equal? (yuanxu-module-source-ref-construction-current?) #f))
        (lambda () (.put! yuanxu-module-source-ref-prototype 'prefix-test-marker #f)))
      (check-equal? (yuanxu-module-source-ref-construction-current?) #f))))
