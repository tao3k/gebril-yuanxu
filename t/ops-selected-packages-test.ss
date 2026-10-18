;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object "./qualification/opentofu/objects.ss"
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/types poo-flow-predicate-contract))
(export ops-selected-packages-test)
(def SelectedPackages. (.get Ops prototypes SelectedPackages))
(def ObjectContract (poo-flow-predicate-contract 'ops/test-object object? (lambda (_v _c) '())))
(def (selection accepted? (other '()) (observe void))
  (let (request
        (.o identity: 'package input-files: '(("selection.json" . "{}"))
            .realize: (lambda (_directory check!)
                        (.o guard-imports: '() guard-forms: '()
                            admission: (.call ObjectContract .admit (if accepted? (.o) #f) #f)
                            admit-current: (lambda () (check!) (observe))))))
    (.o build-graph:
        (.o source-inputs: '() other-projections: other external-packages: (list request)
            admit-current: void))))
(def ops-selected-packages-test
  (test-suite "Native Ops consumes selected external packages"
    (poo-flow-test-case "source guard never repeats external package checking"
      (call-with-temporary-directory "ops-package-guards"
        (lambda (root)
          (def checks 0)
          (def result
            (.call (.cc SelectedPackages.
                     selection: (selection #t '() (lambda () (set! checks (+ checks 1))))
                     directory: root) .run))
          (check-equal? checks 1)
          (.call result sources-current)
          (check-equal? checks 1)
          (.call result admit-current)
          (check-equal? checks 2))))
    (poo-flow-test-case "publishes only after final admission and rechecks an edited guard"
      (call-with-temporary-directory "ops-packages"
        (lambda (root)
          (let (operation (.cc SelectedPackages. 'selection (selection #t) 'directory root))
            (let (result (.call operation .run))
              (check-equal? (file-exists? (.get result guard-entry)) #t)
              (.call result admit-current)
              (call-with-output-file (list path: (.get result guard-entry) truncate: #t)
                (cut display "tampered" <>))
              (check-exception (.call result admit-current) error?))))))
    (poo-flow-test-case "rejects failed admission and unsupported selected projections"
      (call-with-temporary-directory "ops-packages-reject"
        (lambda (root)
          (check-exception
           (.call (.cc SelectedPackages. 'selection (selection #f) 'directory (path-expand "invalid" root)) .run)
           error?)
          (check-exception
           (.call (.cc SelectedPackages. 'selection (selection #t '(unsupported)) 'directory (path-expand "other" root)) .run)
           error?))))
    (poo-flow-test-case "value validation cannot publish after changing package provenance"
      (call-with-temporary-directory "ops-package-admission-mutation"
        (lambda (root)
          (def current? #t)
          (def checks 0)
          (def validated? #f)
          (def request
            (.o identity: 'package input-files: '()
                .realize:
                (lambda (_directory check!)
                  (.o guard-imports: '() guard-forms: '()
                      admission: (begin (set! validated? #t) (set! current? #f)
                                   (.call ObjectContract .admit (.o) #f))
                      admit-current:
                      (lambda () (check!) (set! checks (1+ checks))
                        (unless current? (error "package changed during value admission")))))))
          (def view
            (.o build-graph:
                (.o source-inputs: '() other-projections: '()
                    external-packages: (list request) admit-current: void)))
          (check-exception
            (.call (.cc SelectedPackages. selection: view directory: root) .run) error?)
          (check-equal? validated? #t)
          (check-equal? checks 1))))))
