;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref .cc .put!)
        (only-in :clan/poo/mop element?)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/source/interface
        :yuanxu/module-system/loader/load-path
        :yuanxu/module-system/source/collection
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/projection
        :yuanxu/module-system/loader/objects
        :yuanxu/module-system/authoring/admission
        (only-in :yuanxu/module-system/authoring/roles ModuleAuthoringExecutor.)
        (only-in :yuanxu/poo-clos/objects
                 poo-clos-generic-protocol poo-clos-generic-function
                 poo-clos-compose-method-bundle poo-clos-add-method poo-clos-remove-method)
        (only-in :yuanxu/poo-clos/dispatch poo-clos-call)
        :yuanxu/module-system/authoring/import-policy
        :yuanxu/module-system/authoring/projection)
(export module-authoring-test)
(def RepositoryPolicy
  (.o (:: @ SourceInspectionPolicy.)
      aggregate-imports: '(:example/api)
      package-prefix: ":example/"
      source-roots: '("modules/")
      forbidden-projections: '(parallel-build)))
(def module-authoring-test
  (test-suite "Core source admission without product imports or activation"
    (yuanxu-test-case "authoring receipt identities are stable and do not grant currentness"
      (def interface (yuanxu-module-interface "example" (.o) '()))
      (def result
        (yuanxu-module-authoring-admit-datum interface 'objects '(.o add-profile: #t)))
      (def diagnostic (car (yuanxu-module-authoring-admission-diagnostics result)))
      (check-equal? (.ref result 'kind) 'yuanxu.module-authoring.admission)
      (check-equal? (.ref diagnostic 'kind) 'yuanxu.module-authoring.diagnostic)
      (check-equal? (element? YuanxuModuleAuthoringAdmission result) #t)
      (check-equal? (element? YuanxuModuleAuthoringDiagnostic diagnostic) #t)
      ;; A matching kind does not waive the remaining receipt checks.
      (check-equal? (element? YuanxuModuleAuthoringAdmission (.cc result 'accepted? #t)) #f)
      (check-equal? (element? YuanxuModuleAuthoringDiagnostic
                      (.cc diagnostic 'runtime-executed? #t)) #f))
    (yuanxu-test-case "declarative authoring bundle retains its owner and both dispatch axes"
      ;; Methods have already been composed by the production declaration.
      ;; Do not replay its owned descriptors into a second generic registry.
      (def generic ModuleAuthoringAdmissionGeneric)
      (check-equal? (eq? (.ref generic 'protocol) ModuleAuthoringAdmissionProtocol) #t)
      (check-equal? (length (.ref generic 'methods)) 2)
      (def interface (yuanxu-module-interface "example" (.o) '()))
      (def executor (.o (:: @ ModuleAuthoringExecutor.)))
      (def ordinary-role
        (.o (:: @ (yuanxu-module-authoring-role interface 'objects))))
      (def config-role
        (.o (:: @ (yuanxu-module-authoring-role interface 'config))))
      (check-equal?
        (yuanxu-module-authoring-admission-accepted?
          (poo-clos-call generic executor ordinary-role interface '(stage build)))
        #t)
      (check-equal?
        (yuanxu-module-authoring-admission-accepted?
          (poo-clos-call generic executor config-role interface '(stage build)))
        #f)
      ;; Different protocol objects sharing a label never authorize composition.
      (check-exception
        (poo-clos-compose-method-bundle
          (poo-clos-generic-function 'wrong-owner 4
            protocol: (poo-clos-generic-protocol 'module-system/authoring-admission))
          ModuleAuthoringCoreMethods)
        (lambda (failure)
          (eq? (.ref failure 'code) 'method-bundle-protocol-mismatch))))
    (yuanxu-test-case "inert datum batches preserve native port diagnostics and order"
      (def interface (yuanxu-module-interface "example" (.o) '()))
      (def text "(.o pipeline: (.get ff prototypes pipeline))\n(.o pipeline: (.ref ff pipeline))\n(.o add-profile: #t)\n")
      (def from-port
        (call-with-input-string text
          (cut yuanxu-module-authoring-admit-port interface 'objects <>)))
      (def from-datums
        (yuanxu-module-authoring-admit-datums interface 'objects
          (call-with-input-string text read-all)))
      (def (codes result)
        (map (cut .ref <> 'code)
             (yuanxu-module-authoring-admission-diagnostics result)))
      (check-equal? (yuanxu-module-authoring-admission-accepted? from-port) #f)
      (check-equal? (yuanxu-module-authoring-admission-accepted? from-datums) #f)
      (check-equal? (codes from-datums) (codes from-port))
      ;; Receipt validation is extensible too. A replaced predicate must be
      ;; invoked through the ordinary per-datum producer, before any final
      ;; batch receipt can hide its refusal.
      (def predicate (.ref YuanxuModuleAuthoringAdmission '.element?))
      (def validations 0)
      (dynamic-wind
        (lambda ()
          (.put! YuanxuModuleAuthoringAdmission '.element?
            (lambda (value)
              (set! validations (1+ validations))
              (and (not (= validations 2)) (predicate value)))))
        (lambda ()
          (check-exception
            (yuanxu-module-authoring-admit-datums interface 'objects
              '((def First 1) (def Second 2))) error?)
          (check-equal? validations 2))
        (lambda () (.put! YuanxuModuleAuthoringAdmission '.element? predicate)))
      ;; A contributed qualifier must run for every datum. The batch path must
      ;; retain full invocation after native Generic metadata changes, rather
      ;; than treat the original declarations as an acceptance cache.
      (def calls 0)
      (def before
        (.cc (car (.ref ModuleAuthoringCoreMethods 'methods))
          'identity 'test/authoring-before
          'qualifier 'before
          'body (lambda (_frame . _arguments) (set! calls (1+ calls)) #t)))
      (dynamic-wind
        (cut poo-clos-add-method ModuleAuthoringAdmissionGeneric before)
        (lambda ()
          (def augmented
            (yuanxu-module-authoring-admit-datums interface 'objects
              (call-with-input-string text read-all)))
          (check-equal? calls 3)
          (check-equal? (codes augmented) (codes from-port)))
        (cut poo-clos-remove-method ModuleAuthoringAdmissionGeneric before)))
    (yuanxu-test-case "native Interface and final role admission"
      (let (interface (yuanxu-module-interface "example" (.o) '()))
        (check-equal? (yuanxu-module-interface? interface) #t)
        (check-equal?
         (yuanxu-module-authoring-admission-accepted?
          (yuanxu-module-authoring-admit-datum
           interface 'objects '(.o pipeline: (.get ff prototypes pipeline)))) #t)
        (check-equal?
         (yuanxu-module-authoring-admission-accepted?
          (yuanxu-module-authoring-admit-datum
           interface 'objects '(.o pipeline: (.ref ff pipeline)))) #f)
        (check-equal?
         (yuanxu-module-authoring-admission-accepted?
          (yuanxu-module-authoring-admit-datum
           interface 'objects '(.o add-profile: #t))) #f)
        (check-exception
         (yuanxu-module-authoring-admit-datum interface 'missing '(error "never executed"))
         error?)))
    (yuanxu-test-case "repository policies are explicit and do not leak"
      (check-equal?
       (yuanxu-module-owner-import-datum-observations
        'test '(import :example/api)) '())
      (let (observations
            (yuanxu-authoring-owner-import-datum-observations
             'test '(import (only-in :example/api run)) RepositoryPolicy))
        (check-equal? (length observations) 1)
        (check-equal? (.ref (car observations) 'owner) ':example/api)
        (check-equal? (.ref (car observations) 'runtime-executed?) #f))
      (check-equal?
       (length (yuanxu-build-bootstrap-datum-observations
                'test '(import :example/objects) RepositoryPolicy)) 1)
      (check-equal?
       (length (yuanxu-build-bootstrap-datum-observations
                'test '(import "modules/objects.ss") RepositoryPolicy)) 1)
      (check-equal?
       (length (yuanxu-build-bootstrap-datum-observations
                'test '(parallel-build) RepositoryPolicy)) 1)
      (let (rows (yuanxu-authoring-build-bootstrap-datum-observations
                   'test '(parallel-build) RepositoryPolicy))
        (check-equal? (length rows) 1)
        (check-equal? (.ref (car rows) 'form) 'parallel-build)
        (check-equal? (.ref (car rows) 'owner) 'parallel-build)
        (check-equal? (.ref (car rows) 'runtime-executed?) #f))
      (check-equal?
       (yuanxu-build-bootstrap-datum-observations 'test '(parallel-build)) '())
      (check-equal?
       (yuanxu-build-bootstrap-datum-observations 'test ''(parallel-build) RepositoryPolicy) '()))
    (yuanxu-test-case "collection source policy survives contributor-root lookup"
      (let* ((style (.o (:: @ yuanxu-default-module-style-policy)
                       source-policy: RepositoryPolicy))
             (root (make-yuanxu-contribution-root-module-source
                    'contributions "t/fixtures/source-admission" style-policy: style)))
        (check-exception
         (yuanxu-module-source-collection-locate root '(custom . example))
         (lambda (exception)
           (and (error? exception)
                (string-contains
                 (call-with-output-string (lambda (port) (display-exception exception port)))
                 "YUANXU-MODULE-E008"))))))
    (yuanxu-test-case "source graph and deferred projection never activate a backend"
      (let* ((calls 0)
             (source (make-yuanxu-module-local-source "example/interface.ss"))
             (backend (make-yuanxu-module-loader-backend
                       'example 'local
                       (lambda (_source) (set! calls (+ calls 1)) (.o name: 'example))
                       '()))
             (plans (yuanxu-module-source-refs->lazy-load-plans
                     (list backend) (list source) '((owner . example))))
             (graph (yuanxu-module-auto-imports-resolve (list source) '())))
        (check-equal? calls 0)
        (check-equal? (yuanxu-lazy-load-plan-forced? (car plans)) #f)
        (check-equal? (yuanxu-module-auto-imports-result-source-refs graph)
                      (list source))
        (check-equal? calls 0)))
    (yuanxu-test-case "collection construction remains inert and repository neutral"
      (let (collection
            (make-yuanxu-module-source-collection
             'unavailable 'example "/not-opened-by-construction" "modules"))
        (check-equal? (yuanxu-module-source-collection-identity collection) 'unavailable)
        (check-equal? (yuanxu-module-source-collection-owner collection) 'example)
        (check-equal? (yuanxu-module-source-collection-modules-root collection)
                      "/not-opened-by-construction/modules")))))
