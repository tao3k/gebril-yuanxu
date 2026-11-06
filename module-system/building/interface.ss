;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :yuanxu/module-system/building/products build-output-directory
                 current-build-output-directory current-build-source-directory
                 current-build-compiler-options current-build-module-roots
                 require-build-products! repair-build-products! clean-build-artifacts!)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :yuanxu/module-system/building/source-package call-with-build-input-path)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :yuanxu/module-system/source/deferred-declaration module-entry-action module-binding-action)
        (only-in :yuanxu/module-system/building/source-closure
                 call-with-build-expansion-accounting call-with-build-stage)
        (only-in :yuanxu/module-system/source/observations module-source-read module-source-admit-current!
                 call-with-module-source-read-cache call-with-module-source-callback
                 call-with-module-source-operation-measurement
                 module-source-measure-operation))
(export yuanxu-init-build call-with-init-build-spec)

;; A dynamic association for this Gerbil invocation only, not a spec registry or
;; cached approval. The producer retains its projection and all source checks.
(def current-build-spec-consumer (make-parameter #f))
(def (call-with-init-build-spec prepare dispatch args libdir (entry-source #f))
  (def (run)
    (module-source-measure-operation 'build-main
      (lambda () (consume-init-build-spec prepare dispatch args libdir entry-source))))
  ;; Reuse the runtime build verbosity and existing invocation-local accounting.
  ;; No source observer, approval cache or alternative build entry is installed.
  (def verbosity (string->number (getenv "GERBIL_BUILD_VERBOSE" "0")))
  (if (and verbosity (>= verbosity 2))
    (begin
      ;; real-time has a process-local origin. The wall clock correlates this
      ;; existing span with the caller's spawn/return without blaming their
      ;; different clock origins on process shutdown. CPU is Gambit's clock.
      (displayln "BUILD-STAGE main enter at=" (real-time)
                 " epoch=" (time->seconds (current-time)) " cpu=" (cpu-time))
      (force-output)
      (let-values (((results times)
                    (call-with-module-source-operation-measurement
                      ;; Build timing needs phase clocks and work counters,
                      ;; not VM/GC sampling around every physical file read.
                      ;; Detailed accounting remains an explicit qualification
                      ;; mode of the same existing measurement API.
                      (lambda () (call-with-values run list)) accounting?: (if (>= verbosity 3) 'stages #f))))
        (hash-for-each
          (lambda (key value) (write (list 'BUILD-ACCOUNT key value)) (newline)) times)
        (displayln "BUILD-STAGE main return at=" (real-time)
                   " epoch=" (time->seconds (current-time)) " cpu=" (cpu-time))
        (force-output)
        (apply values results)))
    (run)))
(def (consume-init-build-spec prepare dispatch args libdir entry-source)
  (def produced #f)
  (def consume #f)
  (def spec
    (parameterize ((current-build-output-directory (build-output-directory libdir))
                  (current-build-spec-consumer
                    (cons entry-source
                      (lambda (value owner)
                        (when (and produced (not (eq? produced value)))
                          (error "runtime build must consume one init-owned specification"))
                        (set! produced value)
                        (set! consume owner)))))
      (module-source-measure-operation 'build-specification
        (lambda () (call-with-build-stage 'build-specification prepare)))))
  (if consume
    (begin
      (unless (eq? spec produced)
        (error "runtime build specification lost its init owner"))
      (consume dispatch args libdir))
    (begin
      (when (current-build-module-roots)
        (error "--modules requires an init-owned build specification"))
      (dispatch spec args))))

;; Factories import their public binding through Gerbil. Actual artifact effects
;; retain whole runtime entry initialization. Both are inert at construction and
;; resolve every invocation without storing a procedure or admission result.
(def module-linker
  (module-binding-action "yuanxu/module-system/interface" 'yuanxu-load-modules))
(def write-native-tags
  (module-entry-action 'yuanxu/module-system/building/interface "gerbil/tools/gxtags"
    'gerbil/tools/gxtags#make-tags))
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
(def (yuanxu-init-build source declaration)
  ;; Owned by this init projection, not a global root of the last source Graph.
  ;; Cache offsets/receiver layouts, never successful checks or unrelated cells.
  (def source-current-site (make-slot-cache 'admit-current))
  (def source-spec-site (make-slot-cache 'spec))
  (def init-file (path-expand source))
  ;; The parser permits package: only in the declaration's top-level window
  ;; options. Local windows need no package resolver or second path extent.
  (def package-windows? (memq 'package: declaration))
  (def prepared #f)
  (def input-context-refused? #f)
  (def retained #f)
  (def selection #f)
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
            std-make-spec: (lambda ()
                             ((.get build admit-current))
                             (.get build spec))
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
  (def (check-prepared!)
    (unless prepared (error "init std-make-spec must prepare the source context first"))
    ((.ref/inline prepared source-current-site)))
  (def (current!)
    (with-input-context (build-output-directory) check-prepared!))
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
  (def (build-spec roots)
    (with-input-context (build-output-directory)
      (lambda () (build-spec/in-input-context roots))))
  (def (build-spec/in-input-context roots)
    (def consumer (current-build-spec-consumer))
    (def entry-source (or (and consumer (car consumer))
                          (and prepared (cadr retained))
                          init-file))
    (def request (list (current-build-module-roots) entry-source roots))
    (if prepared
      (unless (equal? request retained)
        (error "init build specification cannot change retained roots within one source epoch"))
      (let* ((init (path-expand source)) (root (path-directory init)))
        (set! prepared
          (module-source-measure-operation 'build-projection
            (lambda ()
              (call-with-build-expansion-accounting 'module-projection
                (lambda ()
                  (build-projector (list (selected!) roots root entry-source)))))))
        (set! retained request)))
    (call-with-build-stage 'spec-current check-prepared!)
    (def value (.ref/inline prepared source-spec-site))
    (.call prepared .admit-spec value)
    (when consumer
      ((cdr consumer) value
        (lambda (dispatch args libdir)
          (run-spec value dispatch args libdir))))
    value)
  ;; The generated read-only identifier calls this accessor, as the existing
  ;; Build role binding does. Reflection receives the actual namespace object.
  (def (module-namespace) (.get (selected!) modules))
  ;; The init consumer already owns this exact specification. Its preparation
  ;; is not a second request: preserve the independent compiler-entry/return
  ;; guards below instead of entering build-spec again during that handoff.
  (def (run-spec spec package-main args requested-libdir)
    (def libdir
      (if (or (null? args) (member (car args) '("compile" "clean")))
        (build-output-directory requested-libdir)
        requested-libdir))
    (parameterize ((current-build-output-directory libdir)
                   (current-build-compiler-options
                     (append (current-build-compiler-options) (if (pair? args) (cdr args) '()))))
      (module-source-measure-operation 'build-dispatch
        (lambda ()
          (with-input-context (or libdir (build-output-directory))
            (lambda () (run-spec/current spec package-main args libdir)))))))
  (def (run-spec/current spec package-main args libdir)
    (.call prepared .admit-spec spec)
    (def compile? (or (null? args) (equal? (car args) "compile")))
    (def (invoke targets (prefix #f))
      (def (run)
        (if prefix (package-main targets args prefix) (package-main targets args)))
      (if compile?
        (call-with-build-input-path libdir run refuse-input-context!
          make-source: (or (current-build-source-directory) (path-directory (cadr retained))))
        (run)))
    (def (dispatch (groups '()))
      (if (pair? groups)
        (for-each
          (lambda (group)
            (invoke (.get group spec) (.get group prefix))) groups)
        (invoke spec)))
    (cond
      (compile?
       ;; Ordinary Gerbil compilation cannot grant publication approval. Explicit
       ;; projection .compile retains the separate artifact issuance boundary.
       (let ((identities (.get prepared compiler-identities))
             (groups (.call prepared .make-groups #t)))
         ;; Installed prerequisites remain native Gerbil imports. The projection
         ;; must never place selected owner source IDs in this prerequisite list;
         ;; every selected source is covered by compiler-identities below.
         (module-source-measure-operation 'build-installed-prerequisites
           (lambda ()
             (let (dependencies (.get prepared dependency-identities))
               (unless (null? dependencies)
                 (require-build-products! dependencies libdir)))))
         (call-with-build-stage 'compiler-inputs
           (lambda ()
             (.call prepared .with-compiler-inputs
               (lambda ()
                 (module-source-measure-operation 'build-product-repair
                   (lambda () (repair-build-products! identities libdir)))
                 (begin0 (module-source-measure-operation 'std-make
                           (lambda ()
                             (call-with-build-expansion-accounting 'std-make
                               (lambda () (dispatch groups)))))
                   (module-source-measure-operation 'build-product-require
                     (lambda () (require-build-products! identities libdir)))
                   (.call prepared .admit-spec spec)))
               refuse-input-context!)))))
      ((equal? (car args) "tags")
       (unless (= (length args) 2)
         (error "tags requires an explicit output file"))
       (let* ((output (path-normalize (cadr args)))
              (temporary (make-temporary-file-name
                           (path-expand ".profile-TAGS-" (path-directory output))))
              (entries (.get prepared build-graph entries))
              (inputs (filter-map (lambda (entry)
                                    (and (memq (.get entry kind) '(source publication))
                                         (.get entry path)))
                                  entries)))
         (when (null? inputs) (error "no selected sources for editor tags"))
         (dynamic-wind void
           (lambda ()
             (check-prepared!)
             (.call prepared .with-compiler-inputs
               (lambda () (write-native-tags (list inputs temporary)))
               refuse-input-context!)
             (check-prepared!)
             (move-file temporary output))
           (lambda () (clear-temporary-file! temporary)))))
      ((equal? (car args) "clean")
       (let (groups (.call prepared .make-groups #f))
         ;; This init-owned Make path only manages files. Its private
         ;; projection never issues an artifact publication. Explicit issuance
         ;; still validates physical products against its own receipt.
         (call-with-build-stage 'clean-outputs
           (lambda ()
             (.call prepared .with-clean-outputs
               (lambda ()
                 (begin0 (call-with-build-stage 'gerbil-clean (lambda () (dispatch groups)))
                   (call-with-build-stage 'clean-product-residue
                     (lambda ()
                       (clean-build-artifacts! (.get prepared compiler-identities) libdir))))))))))
      (else (dispatch))))
  (values
    (.o std-make-spec: build-spec
        admit-current: current! tests: test-source-value)
    module-namespace))
