;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path call-with-build-source-fallbacks package-build-script-path
                 package-library-prefix register-module-build-source!)
        (only-in :tao3k/yuanxu/module-system/source/role-forms module-init-build-roots)

        (only-in :tao3k/yuanxu/module-system/source/build-binding current-module-ffi-build)
        (only-in :tao3k/yuanxu/module-system/building/products
                 build-output-directory
                 current-build-source-directory call-with-selected-output-lock)
        (only-in :gerbil/expander core-import-module core-read-module/sexp expander-context-id)
        (only-in :std/list/list filter-map delete-duplicates/hash)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :tao3k/yuanxu/module-system/source/module-binding module-binding-action)
        (only-in :tao3k/yuanxu/module-system/building/source-closure
                 call-with-build-expansion-accounting)
        (only-in :tao3k/yuanxu/module-system/source/observations
                 module-source-type module-source-name? module-source-read module-source-admit-current!
                 call-with-module-source-read-cache call-with-module-source-callback
                 module-source-measure-operation))
(export yuanxu-init-build)

(def program-projector
  (module-binding-action "tao3k/yuanxu/module-system/building/program"
    'yuanxu-project-compiled-program))
(def program-cleaner
  (module-binding-action "tao3k/yuanxu/module-system/building/program"
    'yuanxu-clean-compiled-program))

;; Factories import their public binding through Gerbil. Actual artifact effects
;; retain whole runtime entry initialization. Both are inert at construction and
;; resolve every invocation without storing a procedure or admission result.
(def module-linker
  (module-binding-action "tao3k/yuanxu/module-system/interface" 'yuanxu-load-modules))
(def build-projector
  (module-binding-action "tao3k/yuanxu/module-system/building/build-projection" 'yuanxu-project-source-spec))
;; Source discovery is demanded separately from compilation/signing.
(def test-source-projector
  (module-binding-action "tao3k/yuanxu/module-system/source/build" 'module-test-source-spec))
(def test-discovery
  (module-binding-action "tao3k/yuanxu/module-system/building/test-projection" 'module-test-projection))
(def test-file-source
  (module-binding-action "tao3k/yuanxu/module-system/building/test-projection" 'module-test-file-source))

;; Init exports inert values. Source preparation begins only on demand.
;; One init module owns one source epoch; changed input requires a fresh session.
(def (yuanxu-init-build source declaration (program #f) (unit #f) (compiled-selection? #f))
  ;; Owned by this init projection, not a global root of the last source Graph.
  ;; Cache offsets/receiver layouts, never successful checks or unrelated cells.
  (def source-current-site (make-slot-cache 'admit-current))
  (def source-spec-site (make-slot-cache 'std-make-spec))
  (def init-file (path-expand source))
  (def root (path-directory init-file))
  (def package-build-roots (module-init-build-roots declaration))
  (def input-context-refused? #f)
  (def selection #f)
  (def compiled (and program (.o value: (program))))
  (def (test-selected-graph)
    (if compiled-selection?
      (begin
        (admit-init-declaration! (module-source-read init-file))
        (let (native (.get compiled value selected-graph))
          (.cc native admit-current:
            (lambda ()
              ;; Explicit currentness still authenticates the live source.
              (def source-graph (.get (selected!) selected-graph))
              ((.get source-graph admit-current))
              ((.get native admit-current))))))
      (.get (selected!) selected-graph)))
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
                selected-graph: (test-selected-graph)
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
        selected-graph: (test-selected-graph)
        spec:
        (append (test-spec)
                (.get (test-source #f 'integration) spec)
                (.get (test-source #f 'qualification) spec))
        admit-current: test-current!
        .select: test-source)))
  (def (refuse-input-context!)
    (set! input-context-refused? #t)
    (error "source projection changed its compiler input context; use a fresh init context"))
  (def (with-input-context output action)
    (when input-context-refused?
      (error "build input context was refused; use a fresh init context"))
    ;; Admit the projected source explicitly. Keep the installed libraries
    ;; ahead of source when resolving runtime bindings during preparation.
    (if (null? package-build-roots)
      (call-with-build-input-path output action refuse-input-context!)
      (call-with-build-input-path output
        (lambda ()
          (def prefix (package-library-prefix root))
          (unless prefix (error "package build roots require a Gerbil package" root))
          (register-module-build-source! root
            (string->symbol (substring prefix 0 (- (string-length prefix) 1)))
            add-load-path?: #f)
          (action))
        refuse-input-context! source-roots: (list root))))
  ;; A consumer may add its native entry targets to the same source epoch
  ;; used by the namespace and test projections.
  (def (prepare-build (retained '()) (command #f))
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
                    (list (if command
                            (begin
                              (admit-init-declaration! (module-source-read init-file))
                              (module-linker
                                (list init-file build-selection: command)))
                            (selected!))
                          retained root (if kind script init-file)))))))))))
  (def (prepare-selection module-ids mount-names)
    (prepare-build '() (.o modules: module-ids mounts: mount-names)))
  (def (compile-selection module-ids mount-names compile)
    (call-with-build-input-path (build-output-directory)
      (lambda ()
        (def build
          (parameterize
              ((current-module-ffi-build
                 (lambda (owner target)
                   (call-with-build-input-path #f
                     (lambda () (compile (list target) owner))
                     refuse-input-context! make-source: owner))))
            (prepare-selection module-ids mount-names)))
        (.call build .with-compiler-inputs
          (lambda ()
            (def source-root (or (current-build-source-directory) root))
            (call-with-build-input-path #f
              (lambda () (compile (.get build std-make-spec) source-root))
              refuse-input-context! make-source: source-root))
          refuse-input-context!))
      refuse-input-context!))
  ;; Reuse the Make selection and its admitted leaf scopes.
  (def (selected-link-entries)
    (call-with-build-source-fallbacks (list (path-directory init-file))
      (lambda ()
        (filter-map
          (lambda (record)
            (let (scope (.get record scope))
              (and (.slot? scope 'program-entry)
                   (let (entry (.get scope program-entry))
                     (let-values (((_prelude owner _namespace _body)
                                   (core-read-module/sexp (.get record source value))))
                       (unless (and (symbol? entry)
                                    (equal? (path-directory (symbol->string owner))
                                            (path-directory (symbol->string entry))))
                         (error "program entry is outside its selected module" (.get record identity) entry))
                       (cons (.get record identity) entry))))))
          (.get (selected!) selected-records)))))
  (def (selected-link-targets library)
    (def package (path-strip-trailing-directory-separator (path-directory library)))
    (def prefix (if (string=? package "") "" (string-append package "/")))
    (def package-parts (if (string=? package "") '() (string-split package #\/)))
    (def targets
      (map (lambda (entry)
             (let (directory (path-strip-trailing-directory-separator
                               (path-directory (symbol->string (cdr entry)))))
               (unless (and (string-prefix? prefix directory)
                            (> (string-length directory) (string-length prefix)))
                 (error "selected program entry is outside its package directory" entry))
               (let (parts (append package-parts '("programs")
                             (string-split (substring directory (string-length prefix)
                                             (string-length directory)) #\/)))
                 (unless (andmap module-source-name? parts)
                   (error "invalid selected program output path" entry))
                 (cons (cdr entry) parts))))
           (selected-link-entries)))
    (def names (map cdr targets))
    (unless (= (length names) (length (delete-duplicates/hash names)))
      (error "selected modules share a link output name" names))
    targets)
  (def (link-destination output parts)
    (foldl (lambda (part parent)
             (let* ((path (path-expand part parent))
                    (kind (module-source-type path)))
               (when (and kind (not (eq? kind 'directory)))
                 (error "expected an ordinary selected program output directory" path))
               path))
           output parts))
  (def (with-link options build)
    (lambda args
      (def (run-build)
        ;; Make prepends the source directory. Resolve installed products
        ;; on the original load path when projecting executable metadata.
        (let (inputs (load-path))
          (dynamic-wind void (lambda () (apply build args))
            (lambda () (set-load-path! inputs)))))
      (def (with-targets prepare action)
        ;; Admit the same source owners before native Make changes its .ssi files.
        (def library (symbol->string (expander-context-id (core-import-module init-file))))
        (def targets (selected-link-targets library))
        (def output (build-output-directory))
        (run-build)
        (def flags (prepare))
        (unless (null? targets)
          (call-with-selected-output-lock output
            (lambda ()
              (for-each (lambda (target destination)
                          (action library (car target) destination flags))
                        targets (map (cut link-destination output <>) (map cdr targets)))))))
      (match args
        ((or [] ["compile" . _])
         (with-targets options
           (lambda (library entry destination flags)
             (create-directory* destination)
             (program-projector
               (list entry destination (list (string->symbol (string-append ":" library)))
                 gsc-options: flags)))))
        (["clean"]
         (with-targets void (lambda (_library _entry destination _flags)
                         (program-cleaner (list destination)))))
        (else (run-build)))))
  ;; The generated read-only identifier calls this accessor, as the existing
  ;; Build role binding does. Reflection receives the actual namespace object.
  (def (build-spec build)
    (with-input-context #f
      (lambda ()
        ;; defbuild-script reads the spec before std/make adds srcdir.
        ;; Both collecting and preparing it can resolve local imports.
        (call-with-build-source-fallbacks (list root)
          (lambda ()
            (def spec (.ref/inline build source-spec-site))
            (.call build .admit-spec spec)
            (.call build .prepare-compiler-contexts)
            spec)))))
  (def window-build-protocol
    (.o fallback-slot-names: (lambda (_window names) (remq '__std-make-spec names))))
  (def (window-namespace mount)
    ;; Namespace reads retain the mounted directory's ordinary admission and
    ;; reflection. The reserved build demand is a lazy, explicit operation.
    (make-object
      supers: (list (.ref (module-namespace) mount))
      protocol: window-build-protocol
      slots:
      (list (cons '__std-make-spec
              ($thunk-slot-spec
                (lambda ()
                  (build-spec (prepare-selection '() (list mount)))))))))
  (def (module-namespace (mount #f))
    (cond
      (mount (window-namespace mount))
      ;; Dynamic Gerbil objects use generation-local Gambit units. The compiled
      ;; program value already identifies native lowering; a static unit-name
      ;; probe must not send a dynamic namespace back to the source reader.
      (compiled (if compiled-selection? (.get compiled value modules) (.get compiled value)))
      ((and unit (##lookup-registered-module unit))
       (error "init has no compiled Module publication" unit))
      (else (.get (selected!) modules))))
  (values
    (.o build: (prepare-build package-build-roots)
        std-make-spec: (build-spec build)
        .make-spec-for: (lambda (module-ids)
                         (build-spec (prepare-selection module-ids '())))
        .with-link: with-link
        .compile-selection: compile-selection
        admit-current:
        (lambda ()
          (with-input-context #f
            (lambda () ((.ref/inline build source-current-site)))))
        tests: test-source-value)
    module-namespace))
