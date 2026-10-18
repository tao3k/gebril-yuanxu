;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :clan/poo/object .get .o .cc .+ .call)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in "./test-projection.ss" module-test-projection module-test-execution)
        (only-in :core/module-system/source/admission module-source-read call-with-module-source-read-cache)
        (only-in :core/module-system/building/build-projection
                 poo-flow-core-project-source-spec))
(export poo-flow-core-init-build)

;; Init exports inert values. Source preparation begins only on demand.
;; One init module owns one source epoch; changed input requires a fresh session.
(def (poo-flow-core-init-build source declaration)
  (def prepared #f)
  (def retained #f)
  (def selection #f)
  (def tests (make-hash-table))
  ;; Compose the existing execution prototype with the guarded source. No
  ;; Graph acquisition, test discovery or process creation occurs here.
  (def (executable-tests source-value (owners #f) (suite #f))
    (def executable
      (.+ source-value
        (.o (:: tests) source: source-value
            execution: (module-test-execution source-value)
            .run: (lambda () (.call (.get tests execution) .run))
            .select: (lambda ((next-owners #f)) (test-source next-owners suite)))))
    (if suite executable
      (.o (:: @ executable)
        integration: (test-source owners 'integration)
        qualification:
        (if owners (test-source owners 'qualification)
          ;; Keep the aggregate facade inert, like init.tests itself. A narrow
          ;; .select must not first discover every eligible owner's sources.
          (executable-tests
            (.o source-root: (path-directory (path-expand source))
                selected-graph: (.get (selected!) selected-graph)
                spec: (.get (test-source #f 'qualification) spec)
                admit-current: (lambda () (test-source #f 'qualification)))
            #f 'qualification)))))
  ;; Reuse the existing namespace's leaf resolver. Neither slot links the other.
  (def (module-view owner scope!)
    (.o identity: owner
        scope: (scope!)
        tests: (test-source (list owner))))
  (def (selected!)
    (unless selection
      (let* ((init (path-expand source))
             (forms (call-with-input-string (module-source-read init) read-all))
             (declared (filter (lambda (form) (and (pair? form) (eq? (car form) 'poo-flow!))) forms)))
        (unless (equal? declared (list declaration))
          (error "imported init declaration differs from its source; use a fresh source context"))
        (set! selection (poo-flow-load-modules init module-view: module-view))))
    ((.get selection admit-current))
    selection)
  (def (test-current!)
    (unless selection (error "init.test-spec must select its source context first"))
    (call-with-module-source-read-cache
      (lambda ()
        ((.get selection admit-current))
        (hash-for-each (lambda (_owners projection) ((.get projection admit-current))) tests))))
  (def (test-source (owners #f) (suite #f))
    (def view (selected!))
    (def key (list suite owners))
    (if (hash-key? tests key)
      (let (projection (hash-ref tests key))
        ;; Independent requests must still observe changed test/source inputs.
        ((.get projection admit-current))
        projection)
      (let (projection
             (executable-tests
               (.cc (module-test-projection view owners suite)
                 'source-root (path-directory (path-expand source))) owners suite))
        ;; module-test-projection has just checked the complete snapshot. Only
        ;; inert POO composition and insertion into this private cache follow;
        ;; there is no import, caller handoff or execution requiring a recheck.
        (hash-put! tests key projection)
        projection)))
  (def (test-spec (owners #f))
    (def projection (test-source owners))
    ;; test-source already admits this projection. A narrow request must not
    ;; traverse every previously discovered suite; explicit test-current! is
    ;; the aggregate epoch check, not a prerequisite for a single module.
    (.get projection spec))
  ;; This executable POO value shares the existing selection/projection cache.
  ;; Neither constructing it nor importing init acquires Graph or file inputs.
  (def test-source-value
    (executable-tests
      (.o source-root: (path-directory (path-expand source))
        selected-graph: (.get (selected!) selected-graph)
        spec: (test-spec)
        admit-current: test-current!
        .select: test-source)))
  (def (current!)
    (unless prepared (error "init.build-spec must prepare the source context first"))
    ((.get prepared admit-current)))
  (def (build-spec roots)
    (if prepared
      (unless (equal? roots retained)
        (error "init build specification cannot change retained roots within one source epoch"))
      (let* ((init (path-expand source)) (root (path-directory init)))
        (set! prepared
          (poo-flow-core-project-source-spec (selected!) roots root (path-expand "build.ss" root)))
        (set! retained roots)))
    (current!)
    (.get prepared spec))
  ;; The generated read-only identifier calls this accessor, as the existing
  ;; Build role binding does. Reflection receives the actual namespace object.
  (def (module-namespace) (.get (selected!) modules))
  (values build-spec current! test-spec test-current! test-source-value module-namespace))
