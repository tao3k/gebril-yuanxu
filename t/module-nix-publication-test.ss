;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :clan/poo/object .def .get .call .slot? .ref/cached object?)
        (only-in :core/modules/nix/objects NixSource.)
        (only-in :core/types poo-flow-validation-evidence-accepted?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/module-system/interface poo-flow-load-modules))
(export module-nix-publication-test)
(def module-nix-publication-test
  (test-suite "Nix is a declarative Core Module, not a global facade"
    (poo-flow-test-case "selected source publishes native Sources without realizing packages"
      (call-with-temporary-directory "nix-module-publication"
        (lambda (directory)
          (let* ((path (path-expand "init.ss" directory))
                 (source (path-expand "../modules" (path-directory (this-source-file)))))
            (call-with-output-file path
              (lambda (port)
                (write `(poo-flow! mode: explicit source: ,source (nix)) port)))
            (let* ((view (poo-flow-load-modules path))
                   (scope (.get view modules nix))
                   (prototype (.get scope prototypes Source)))
              (check-equal? (object? prototype) #t)
              (check-equal? (.slot? prototype '.build) #t)
              (check-equal? (.slot? (.get scope types) 'FlakeSource) #t)
              (check-equal? (.slot? (.get scope prototypes FlakeSource) '.prepare) #t)
              (check-equal? (poo-flow-validation-evidence-accepted?
                              (.call (.get scope types Source) .admit prototype #f)) #f)
              (check-equal? (.get view selected-graph module-order) '(nix))
              (check-equal? (.get view build-graph external-packages) '())
              ((.get view admit-current)))))))
    (poo-flow-test-case "cached realization removes only an adjacent source check, never the Nix identity query"
      ;; The phase object and guards are production code. Only the two external
      ;; commands are inert probes; real Nix is retained in the AWS integration.
      (def instantiations 0)
      (def realizations 0)
      (def source-checks 0)
      (def current? #t)
      (def mutate? #f)
      (.def (Source @ NixSource.)
        .instantiate:
        (lambda ()
          (set! instantiations (+ instantiations 1))
          (when mutate? (set! current? #f))
          "/nix/store/test-source.drv")
        .realize:
        (lambda (_derivation)
          (set! realizations (+ realizations 1))
          "/nix/store/test-artifact"))
      (def prepared
        (.call Source .prepare
          (lambda ()
            (set! source-checks (+ source-checks 1))
            (unless current? (error "source changed during external query")))))
      (check-equal? (.ref/cached prepared 'artifact) #f)
      (.call prepared admit-current)
      (check-equal? source-checks 4) ; preflight, before/after realization, after query
      (check-equal? instantiations 2)
      (check-equal? realizations 1)
      (def previous (.get prepared artifact))
      (set! source-checks 0)
      (.call prepared admit-current)
      (check-equal? source-checks 2) ; before/after the fresh query
      (check-equal? instantiations 3)
      (check-equal? realizations 1)
      (set! mutate? #t)
      (check-exception (.call prepared admit-current) error?)
      (check-equal? instantiations 4)
      (check-equal? (.get prepared artifact) previous)
      (check-exception (.call prepared admit-current) error?)
      (check-equal? instantiations 4))))
