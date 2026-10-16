;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .o .ref)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :core/observability/testing-case poo-flow-test-case)
        :core/module-system/source/interface
        :core/module-system/loader/load-path
        :core/module-system/source/collection
        :core/module-system/source/objects
        :core/module-system/source/projection
        :core/module-system/loader/objects
        :core/module-system/authoring/admission
        :core/module-system/authoring/import-policy
        :core/module-system/authoring/projection)
(export module-authoring-test)
(def RepositoryPolicy
  (.o (:: @ SourceInspectionPolicy.)
      aggregate-imports: '(:example/api)
      package-prefix: ":example/"
      source-roots: '("modules/")
      forbidden-projections: '(parallel-build)))
(def module-authoring-test
  (test-suite "Core source admission without product imports or activation"
    (poo-flow-test-case "native Interface and final role admission"
      (let (interface (poo-flow-module-interface "example" (.o) '()))
        (check-equal? (poo-flow-module-interface? interface) #t)
        (check-equal?
         (poo-flow-module-authoring-admission-accepted?
          (poo-flow-module-authoring-admit-datum
           interface 'objects '(.o pipeline: (.get ff prototypes pipeline)))) #t)
        (check-equal?
         (poo-flow-module-authoring-admission-accepted?
          (poo-flow-module-authoring-admit-datum
           interface 'objects '(.o pipeline: (.ref ff pipeline)))) #f)
        (check-equal?
         (poo-flow-module-authoring-admission-accepted?
          (poo-flow-module-authoring-admit-datum
           interface 'objects '(.o add-profile: #t))) #f)
        (check-exception
         (poo-flow-module-authoring-admit-datum interface 'missing '(error "never executed"))
         error?)))
    (poo-flow-test-case "repository policies are explicit and do not leak"
      (check-equal?
       (poo-flow-module-owner-import-datum-observations
        'test '(import :example/api)) '())
      (let (observations
            (poo-flow-authoring-owner-import-datum-observations
             'test '(import (only-in :example/api run)) RepositoryPolicy))
        (check-equal? (length observations) 1)
        (check-equal? (.ref (car observations) 'owner) ':example/api)
        (check-equal? (.ref (car observations) 'runtime-executed?) #f))
      (check-equal?
       (length (poo-flow-build-bootstrap-datum-observations
                'test '(import :example/objects) RepositoryPolicy)) 1)
      (check-equal?
       (length (poo-flow-build-bootstrap-datum-observations
                'test '(import "modules/objects.ss") RepositoryPolicy)) 1)
      (check-equal?
       (length (poo-flow-build-bootstrap-datum-observations
                'test '(parallel-build) RepositoryPolicy)) 1)
      (let (rows (poo-flow-authoring-build-bootstrap-datum-observations
                   'test '(parallel-build) RepositoryPolicy))
        (check-equal? (length rows) 1)
        (check-equal? (.ref (car rows) 'form) 'parallel-build)
        (check-equal? (.ref (car rows) 'owner) 'parallel-build)
        (check-equal? (.ref (car rows) 'runtime-executed?) #f))
      (check-equal?
       (poo-flow-build-bootstrap-datum-observations 'test '(parallel-build)) '())
      (check-equal?
       (poo-flow-build-bootstrap-datum-observations 'test ''(parallel-build) RepositoryPolicy) '()))
    (poo-flow-test-case "collection source policy survives contributor-root lookup"
      (let* ((style (.o (:: @ poo-flow-default-module-style-policy)
                       source-policy: RepositoryPolicy))
             (root (make-poo-flow-contribution-root-module-source
                    'contributions "t/fixtures/source-admission" style-policy: style)))
        (check-exception
         (poo-flow-module-source-collection-locate root '(custom . example))
         error?)))
    (poo-flow-test-case "source graph and plan projection never activate a backend"
      (let* ((calls 0)
             (source (make-poo-flow-module-local-source "example/interface.ss"))
             (backend (make-poo-flow-module-loader-backend
                       'example 'local
                       (lambda (_source) (set! calls (+ calls 1)) (.o name: 'example))
                       '()))
             (plans (poo-flow-module-source-refs->lazy-load-plans
                     (list backend) (list source) '((owner . example))))
             (graph (poo-flow-module-auto-imports-resolve (list source) '())))
        (check-equal? calls 0)
        (check-equal? (poo-flow-lazy-load-plan-forced? (car plans)) #f)
        (check-equal? (poo-flow-module-auto-imports-result-source-refs graph)
                      (list source))
        (check-equal? calls 0)))
    (poo-flow-test-case "collection construction remains inert and repository neutral"
      (let (collection
            (make-poo-flow-module-source-collection
             'unavailable 'example "/not-opened-by-construction" "modules"))
        (check-equal? (poo-flow-module-source-collection-identity collection) 'unavailable)
        (check-equal? (poo-flow-module-source-collection-owner collection) 'example)
        (check-equal? (poo-flow-module-source-collection-modules-root collection)
                      "/not-opened-by-construction/modules")))))
