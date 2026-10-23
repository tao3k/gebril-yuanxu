;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :clan/poo/object .get .o .cc .+ .call)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in "./test-projection.ss" module-test-projection module-test-file-source module-test-execution)
        (only-in :yuanxu/module-system/source/admission module-source-read call-with-module-source-read-cache
                 module-source-measure-operation))
(export yuanxu-init-build)

;; Like testing-executor, these promises retain native bindings, never a Graph,
;; source check or approval. Importing init must not import the Reader/compiler
;; or artifact machinery. Each explicit demand still runs the original owner.
(def module-linker
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :yuanxu/module-system/interface))
      (eval-syntax 'yuanxu-load-modules))))
(def build-projector
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :yuanxu/module-system/building/build-projection))
      (eval-syntax 'yuanxu-project-source-spec))))
(def artifact-cleaners
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :yuanxu/module-system/building/artifacts))
      (eval-syntax '(cons invalidate-build-artifacts! clean-build-artifacts!)))))

;; Init exports inert values. Source preparation begins only on demand.
;; One init module owns one source epoch; changed input requires a fresh session.
(def (yuanxu-init-build source declaration)
  (def init-file (path-expand source))
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
            build:
            ((force build-projector) (selected!) '()
              (path-directory init-file) init-file
              demand: source-value)
            std-make-spec: (lambda ()
                             ((.get build admit-current))
                             (.get build spec))
            execution: (module-test-execution source-value
                         (lambda () (.get tests build)))
            .run: (lambda () (.call (.get tests execution) .run))
            .for-files: file-tests
            .select: (lambda ((next-owners #f)) (test-source next-owners suite)))))
    (if suite executable
      (.o (:: @ executable)
        integration: (test-source owners 'integration)
        qualification:
        (if owners (test-source owners 'qualification)
          ;; Keep the aggregate facade inert, like the init export tests slot itself. A narrow
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
             (declared (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms)))
        (unless (equal? declared (list declaration))
          (error "imported init declaration differs from its source; use a fresh source context"))
        (def linker (module-source-measure-operation 'linker-import (cut force module-linker)))
        (set! selection (module-source-measure-operation 'context
                          (cut linker init module-view: module-view)))))
    (module-source-measure-operation 'selection-current (.get selection admit-current))
    selection)
  (def (test-current!)
    (unless selection (error "init tests must select their source context first"))
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
  (def (file-tests files)
    (def file-source (module-test-file-source files))
    (executable-tests
      (.cc file-source
        'source-root (path-directory init-file)
        'selected-graph
        (let (view (selected!))
          (module-source-measure-operation 'selected-graph (lambda () (.get view selected-graph))))
        'admit-current
        (lambda ()
          ;; selected! already admits the current selection, including the
          ;; package boundary when realized. Do not invoke that guard twice.
          (selected!)
          ((.get file-source admit-current))))))
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
    (unless prepared (error "init std-make-spec must prepare the source context first"))
    ((.get prepared admit-current)))
  (def (build-spec roots)
    (if prepared
      (unless (equal? roots retained)
        (error "init build specification cannot change retained roots within one source epoch"))
      (let* ((init (path-expand source)) (root (path-directory init)))
        (set! prepared
          ((force build-projector) (selected!) roots root (path-expand "build.ss" root)))
        (set! retained roots)))
    (current!)
    (.get prepared spec))
  ;; The generated read-only identifier calls this accessor, as the existing
  ;; Build role binding does. Reflection receives the actual namespace object.
  (def (module-namespace) (.get (selected!) modules))
  ;; Execute the installed SDK's dispatcher unchanged. Core only owns the
  ;; before/after boundary and the retained result of a successful compile.
  (def (build-run roots package-main args (libdir (path-expand "lib" (gerbil-path))))
    ;; Pass the admitted value to the SDK dispatcher. The compile boundary
    ;; below owns fresh checks before and after its callback; the callback
    ;; must not re-enter source preparation to obtain the same specification.
    (def spec (build-spec roots))
    (def (dispatch) (package-main spec args))
    (cond
      ((or (null? args) (equal? (car args) "compile"))
       (.call prepared .compile libdir dispatch))
      ((equal? (car args) "clean")
       (let (cleaners (force artifact-cleaners))
         ((car cleaners) (.get prepared build-graph))
         ;; Loading cleaners and invalidating issuance precede SDK cleanup.
         ;; Retain the freshness check at that exact boundary.
         (current!)
         (begin0 (dispatch)
           ((cdr cleaners) (.get prepared compiler-identities) libdir))))
      (else (dispatch))))
  (values
    (.o std-make-spec: build-spec std-make-run: build-run
        admit-current: current! tests: test-source-value)
    module-namespace))
