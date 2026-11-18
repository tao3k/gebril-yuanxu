;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Module System init projections. Infrastructure, not a selected module.
(import (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path call-with-build-source-fallbacks package-build-script-path
                 package-library-prefix register-module-build-source!)
        (only-in :tao3k/yuanxu/module-system/source/role-forms module-init-build-roots)
        (only-in :tao3k/yuanxu/module-system/building/products
                 build-output-directory current-build-dispatch)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :std/list/list filter-map delete-duplicates/hash)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-layout make-slot-cache)
        (only-in :tao3k/yuanxu/module-system/source/module-binding module-binding-action)
        (only-in :tao3k/yuanxu/module-system/building/source-closure
                 call-with-build-expansion-accounting)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-type module-source-read module-source-admit-current!
                 call-with-module-source-read-cache call-with-module-source-callback
                 module-source-measure-operation))
(export yuanxu-init-build)

(def program-projector
  (module-binding-action "tao3k/yuanxu/module-system/building/program"
    'yuanxu-project-compiled-program))

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
  (def (prepare-build (retained '()) (demand #f))
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
                    (list (if demand
                            (begin
                              (admit-init-declaration! (module-source-read init-file))
                              (module-linker (list init-file build-window: demand)))
                            (selected!))
                          retained root (if kind script init-file)))))))))))
  ;; Reuse the Make selection and its admitted leaf scopes.
  (def (selected-link-entries)
    (call-with-build-source-fallbacks (list (path-directory init-file))
      (lambda ()
        (filter-map
          (lambda (record)
            (let (scope (.get record scope))
              (and (.slot? scope 'program-entry)
                   (cons (.get record identity) (.get scope program-entry)))))
          (.get (selected!) selected-records)))))
  (def (init-library)
    (symbol->string (expander-context-id (core-import-module init-file))))
  (def (link-root)
    (path-expand "programs"
      (path-expand (path-directory (init-library)) (build-output-directory))))
  (def (with-link options build)
    (lambda args
      (def (run-build)
        ;; Make prepends the source directory. Resolve installed products
        ;; on the original load path when projecting executable metadata.
        (let (inputs (load-path))
          (dynamic-wind void (lambda () (apply build args))
            (lambda () (set-load-path! inputs)))))
      (match args
        ((or [] ["compile" . _])
         ;; Source admissions must precede creating the compiled .ssi files.
         (def entries (selected-link-entries))
         (def package-directory (path-directory (init-library)))
         (def (program-name entry)
           (let (directory (path-directory (symbol->string (cdr entry))))
             (unless (and (string-prefix? package-directory directory)
                          (> (string-length directory) (string-length package-directory)))
               (error "selected program entry is outside its package directory" entry))
             (path-strip-trailing-directory-separator
               (substring directory (string-length package-directory) (string-length directory)))))
         (def names (map program-name entries))
         (unless (= (length names) (length (delete-duplicates/hash names)))
           (error "selected modules share a link output name" names))
         (def init (string->symbol (string-append ":" (init-library))))
         (def root (link-root))
         (run-build)
         (def flags (options))
         (for-each
           (lambda (entry name)
             (let (destination (path-expand name root))
               (create-directory* destination)
               (program-projector (list (cdr entry) destination (list init) gsc-options: flags))))
           entries names))
        (["clean"]
         (run-build)
         (let (root (link-root))
           (when (file-exists? root) (delete-file-or-directory root))))
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
            (let (dispatch (current-build-dispatch))
              (if (and dispatch (.ref build 'unified-source?))
                (dispatch build spec)
                (.call build .prepare-compiler-contexts)))
            spec)))))
  (def (window-namespace mount)
    (.o __std-make-spec: (build-spec (prepare-build '() (cons mount #f)))
        no-applicable-method:
        (lambda (_self leaf)
          (.o __std-make-spec: (build-spec (prepare-build '() (cons mount leaf)))))))
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
        .with-link: with-link
        admit-current:
        (lambda ()
          (with-input-context #f
            (lambda () ((.ref/inline build source-current-site)))))
        tests: test-source-value)
    module-namespace))
