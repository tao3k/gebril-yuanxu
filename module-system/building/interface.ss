;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :yuanxu/module-system/building/products current-build-module-roots)
        (only-in :yuanxu/module-system/building/source-package call-with-build-input-path package-build-script-path)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :yuanxu/module-system/source/deferred-declaration module-binding-action)
        (only-in :yuanxu/module-system/building/source-closure
                 call-with-build-expansion-accounting call-with-build-stage)
        (only-in :yuanxu/module-system/source/observations module-source-type module-source-read module-source-admit-current!
                 call-with-module-source-read-cache call-with-module-source-callback
                 module-source-measure-operation))
(export yuanxu-init-build)

;; Factories import their public binding through Gerbil. Actual artifact effects
;; retain whole runtime entry initialization. Both are inert at construction and
;; resolve every invocation without storing a procedure or admission result.
(def module-linker
  (module-binding-action "yuanxu/module-system/interface" 'yuanxu-load-modules))
(def build-projector
  (module-binding-action "yuanxu/module-system/building/build-projection" 'yuanxu-project-source-spec))
(def init-compiler-roots
  (module-binding-action "yuanxu/module-system/source/init" 'module-init-compiler-source-roots))
;; Source discovery is demanded separately from compilation/signing.
(def test-source-projector
  (module-binding-action "yuanxu/module-system/source/build" 'module-test-source-spec))
(def test-discovery
  (module-binding-action "yuanxu/module-system/building/test-projection" 'module-test-projection))
(def test-file-source
  (module-binding-action "yuanxu/module-system/building/test-projection" 'module-test-file-source))

;; Init exports inert values. Source preparation begins only on demand.
;; One init module owns one source epoch; changed input requires a fresh session.
(def (yuanxu-init-build source declaration (program #f) (unit #f))
  ;; Owned by this init projection, not a global root of the last source Graph.
  ;; Cache offsets/receiver layouts, never successful checks or unrelated cells.
  (def source-current-site (make-slot-cache 'admit-current))
  (def source-spec-site (make-slot-cache 'spec))
  (def init-file (path-expand source))
  ;; The parser permits package: only in the declaration's top-level window
  ;; options. Local windows need no package resolver or second path extent.
  (def package-windows? (memq 'package: declaration))
  (def input-context-refused? #f)
  (def selection #f)
  (def compiled (and program (.o modules: (program))))
  (def tests (make-hash-table))
  ;; Publish guarded test inputs and native Make specifications. No
  ;; Graph acquisition, test discovery or process creation occurs here.
  (def (executable-tests source-value (owners #f) (suite #f))
    (def executable
      (.+ source-value
        (.o (:: tests) source: source-value
            build:
            (test-source-projector (list (lambda () (selected!)) source-value
              (path-directory init-file) init-file
              (if (.slot? source-value 'std-make-spec)
                (.get source-value std-make-spec) '())))
            std-make-spec: (test-build-spec (.get tests build))
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
  (def (admit-init-declaration! text)
    (let* ((forms (call-with-input-string text read-all))
           (declared (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms)))
      (unless (equal? declared (list declaration))
        (error "imported init declaration differs from its source; use a fresh source context"))))
  (def (selected!)
    (unless selection
      (admit-init-declaration! (module-source-read init-file))
      (let (init (path-expand source))
        (set! selection (module-source-measure-operation 'context
                          (lambda () (module-linker (list init)))))))
    (module-source-measure-operation 'selection-current (.get selection admit-current))
    selection)
  (def (test-current!)
    ;; A native test build can request currentness before demanding its spec.
    ;; Select here so the first request authenticates the same source context.
    (call-with-module-source-read-cache
      (lambda ()
        (selected!)
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
               (.cc (call-with-module-source-callback
                      (lambda () (test-discovery (list view owners suite))))
                 'source-root (path-directory (path-expand source))) owners suite))
        ;; module-test-projection has just checked the complete snapshot. Only
        ;; inert POO composition and insertion into this private cache follow;
        ;; there is no import, caller handoff or execution requiring a recheck.
        (hash-put! tests key projection)
        projection)))
  (def (file-tests files (inputs '()) (std-make-spec '()))
    ;; The caller supplies existing package-owned runtime declarations. They
    ;; refine only demanded support targets; they never expand the test roster.
    (source-tests (.cc (call-with-module-source-callback
                         (lambda () (test-file-source (list files inputs))))
                    std-make-spec: std-make-spec)))
  (def (test-build-spec build)
    ((.get build admit-current))
    (def spec (.get build spec))
    spec)
  (def (source-tests file-source)
    ;; An explicit runtime file test does not select business Modules. Keep its
    ;; init owner current without evaluating declarations/roles; if a Graph is
    ;; later demanded, selected! adds the original complete admission boundary.
    (def init-input (cons init-file (module-source-read init-file)))
    (admit-init-declaration! (cdr init-input))
    (executable-tests
      (.o (:: @ file-source)
        source-root: (path-directory init-file)
        selected-graph:
        (let (view (selected!))
          (module-source-measure-operation 'selected-graph (lambda () (.get view selected-graph))))
        admit-current:
        (lambda ()
          (when selection (selected!))
          (call-with-module-source-read-cache
            (lambda ()
              (module-source-admit-current! (list init-input) "test init source changed")
              ((.get file-source admit-current))))))))
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
  (def (compiler-source-roots)
    ;; Only the bound init declaration can name native checkout inputs.
    (init-compiler-roots (list declaration init-file)))
  (def (refuse-input-context!)
    (set! input-context-refused? #t)
    (error "source projection changed its compiler input context; use a fresh init context"))
  (def (with-input-context output action)
    (when input-context-refused?
      (error "build input context was refused; use a fresh init context"))
    (call-with-build-input-path output
      (if package-windows?
        (lambda ()
          (call-with-build-input-path output action refuse-input-context!
            source-roots: (compiler-source-roots)))
        action)
      refuse-input-context!))
  (def (prepare-build)
    (with-input-context #f
      (lambda ()
        (module-source-measure-operation 'build-projection
          (lambda ()
            (call-with-build-expansion-accounting 'module-projection
              (lambda ()
                (let* ((root (path-directory init-file))
                       (script (package-build-script-path root))
                       (kind (module-source-type script)))
                  (when (and kind (not (eq? kind 'regular)))
                    (error "package build script must be a regular source" script))
                  (build-projector
                    (list (selected!) '() root (if kind script init-file)))))))))))
  ;; The generated read-only identifier calls this accessor, as the existing
  ;; Build role binding does. Reflection receives the actual namespace object.
  (def (module-namespace)
    (cond
      ;; Dynamic Gerbil objects use generation-local Gambit units. The compiled
      ;; program value already identifies native lowering; a static unit-name
      ;; probe must not send a dynamic namespace back to the source reader.
      (compiled (.get compiled modules))
      ((and unit (##lookup-registered-module unit))
       (error "init has no compiled Module publication" unit))
      (else (.get (selected!) modules))))
  (values
    (.o build: (prepare-build)
        std-make-spec:
        (with-input-context #f
          (lambda ()
            (def spec (.ref/inline build source-spec-site))
            (.call build .admit-spec spec)
            (.call build .prepare-compiler-contexts)
            spec))
        admit-current:
        (lambda ()
          (with-input-context #f
            (lambda () ((.ref/inline build source-current-site)))))
        tests: test-source-value)
    module-namespace))
