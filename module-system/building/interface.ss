;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :clan/poo/object .get .o .cc .+ .call .slot?)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in "./test-projection.ss" module-test-projection module-test-file-source
                 module-test-directory-source module-test-execution)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-admit-current!
                 call-with-module-source-read-cache
                 module-source-measure-operation))
(export yuanxu-init-build call-with-init-build-spec)

;; A dynamic association for this Gerbil invocation only, not a spec registry or
;; cached approval. The producer retains its projection and all source checks.
(def current-build-spec-consumer (make-parameter #f))
(def (call-with-init-build-spec prepare dispatch args libdir)
  ;; This callback mutates issuance state across prepare's dynamic boundary.
  ;; Keep that state explicit; compiler inference must not freeze its initial
  ;; false value and classify the eventual Gerbil consumer as non-callable.
  (def association (vector #f #f))
  (def spec
    (parameterize ((current-build-spec-consumer
                    (lambda (value owner)
                      (when (and (vector-ref association 0)
                                 (not (eq? (vector-ref association 0) value)))
                        (error "native build must consume one init-owned specification"))
                      (unless (procedure? owner) (error "native build consumer must be callable"))
                      (vector-set! association 0 value)
                      (vector-set! association 1 owner))))
      (prepare)))
  (def consume (vector-ref association 1))
  (if consume
    (begin
      (unless (eq? spec (vector-ref association 0))
        (error "native build specification lost its init owner"))
      (consume dispatch args libdir))
    (dispatch spec args)))

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
;; Source discovery is demanded separately from compilation/signing.
(def test-source-projector
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core))
      (eval-syntax '(import (only-in :yuanxu/module-system/source/build module-test-source-spec)))
      (eval-syntax 'module-test-source-spec))))
(def artifact-cleaners
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :yuanxu/module-system/building/artifacts))
      (eval-syntax '(list invalidate-build-artifacts! clean-build-artifacts!
                         repair-build-products! require-build-products!
                         retain-test-support-subset!)))))

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
            ((force test-source-projector) (lambda () (selected!)) source-value
              (path-directory init-file) init-file
              (if (.slot? source-value 'std-make-spec)
                (.get source-value std-make-spec) '()))
            std-make-spec: (lambda () (test-build-spec tests))
            execution: (module-test-execution source-value
                         (lambda () (.get tests build)))
            .run: (lambda () (.call (.get tests execution) .run))
            .compile: (lambda () (.call (.get tests execution) .compile))
            .for-files: file-tests
            .for-directory: directory-tests
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
  (def (admit-init-declaration! text)
    (let* ((forms (call-with-input-string text read-all))
           (declared (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms)))
      (unless (equal? declared (list declaration))
        (error "imported init declaration differs from its source; use a fresh source context"))))
  (def (selected!)
    (unless selection
      (admit-init-declaration! (module-source-read init-file))
      (let (init (path-expand source))
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
  (def (file-tests files (inputs '()) (std-make-spec '()))
    ;; The caller supplies existing package-owned native declarations. They
    ;; refine only demanded support targets; they never expand the test roster.
    (source-tests (.cc (module-test-file-source files inputs)
                    std-make-spec: std-make-spec)))
  (def (directory-tests directory (excluded '()))
    (source-tests (module-test-directory-source
                   (path-expand directory (path-directory init-file)) excluded)))
  (def (source-tests file-source)
    ;; An explicit native file test does not select business Modules. Keep its
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
  (def (current!)
    (unless prepared (error "init std-make-spec must prepare the source context first"))
    ((.get prepared admit-current)))
  ;; The official Gerbil consumer owns both compile phases. A test source is a
  ;; POO declaration, not a command, environment selector or executable plan.
  (def (test-build-spec tests)
    (def build (.get tests build))
    ((.get build admit-current))
    (def value (.get build spec))
    (when (current-build-spec-consumer)
      ((current-build-spec-consumer) value
        (lambda (dispatch args libdir) (run-test-spec tests dispatch args libdir))))
    value)
  (def (run-test-spec tests dispatch args libdir)
    (def build (.get tests build))
    ((.get build admit-current))
    (cond
      ((or (null? args) (equal? (car args) "compile"))
       (def source (.get (.get build build-graph) build-publication))
       (if (.call source .available?)
         ((.get build admit-artifacts))
         (.call build .compile (.get build output-directory)
           (lambda ()
             (dispatch (.get build spec) args #f
               ((.get build compile-output))))))
       ;; Each independently selected Suite gets a proof-preserving subset of
       ;; the one native build. No per-Case compiler or test verdict is cached.
       (def transfer (list-ref (force artifact-cleaners) 4))
       (def retained
         (if (.slot? (.get tests source) 'std-make-spec)
           (.get tests source std-make-spec) '()))
       (for-each
         (lambda (file)
           (def consumer (.get (file-tests (list file) '() retained) build))
           (transfer build consumer))
         (.get tests spec)))
      ((equal? (car args) "spec") (dispatch (.get build spec) args))
      (else (error "test support lifecycle requires Gerbil compile or spec" args)))
    ((.get build admit-current)))
  (def (build-spec roots)
    (if prepared
      (unless (equal? roots retained)
        (error "init build specification cannot change retained roots within one source epoch"))
      (let* ((init (path-expand source)) (root (path-directory init)))
        (set! prepared
          ((force build-projector) (selected!) roots root (path-expand "build.ss" root)))
        (set! retained roots)))
    (current!)
    (def value (.get prepared spec))
    (when (current-build-spec-consumer)
      ((current-build-spec-consumer) value
        (lambda (dispatch args libdir)
          (run-spec value dispatch args libdir
            (.get prepared std-make-specs)))))
    value)
  ;; The generated read-only identifier calls this accessor, as the existing
  ;; Build role binding does. Reflection receives the actual namespace object.
  (def (module-namespace) (.get (selected!) modules))
  ;; The init consumer already owns this exact specification. Its preparation
  ;; is not a second request: preserve the independent compiler-entry/return
  ;; guards below instead of entering build-spec again during that handoff.
  (def (run-spec spec package-main args libdir native-specs)
    (def (dispatch (groups #f))
      (if (and groups (ormap (cut .get <> prefix) groups))
        (for-each
          (lambda (group)
            (if (.get group prefix)
              (package-main (.get group spec) args (.get group prefix))
              (package-main (.get group spec) args))) groups)
        (package-main spec args)))
    (cond
      ((or (null? args) (equal? (car args) "compile"))
       ;; Ordinary Gerbil compilation cannot grant publication approval. Explicit
       ;; projection .compile retains the separate artifact issuance boundary.
       (let ((products (force artifact-cleaners))
             (identities (.get prepared compiler-identities)))
         (.call prepared .with-compiler-inputs
           (lambda ()
             ((list-ref products 2) identities libdir)
             (begin0 (dispatch native-specs)
               ((list-ref products 3) identities libdir))))))
      ((equal? (car args) "clean")
       (let (cleaners (force artifact-cleaners))
         ((car cleaners) (.get prepared build-graph))
         ;; Loading cleaners and invalidating issuance precede Gerbil cleanup.
         ;; Retain the freshness check at that exact boundary.
         (current!)
         (begin0 (dispatch native-specs)
           ((cadr cleaners) (.get prepared compiler-identities) libdir))))
      (else (dispatch))))
  (values
    (.o std-make-spec: build-spec
        admit-current: current! tests: test-source-value)
    module-namespace))
