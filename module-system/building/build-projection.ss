;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Project selected sources to ordinary std/build-script specifications.
;;; std/make owns compilation, dependency scheduling and clean.
(import (only-in :std/string/path path-absolute?)
        (only-in "./artifacts.ss" call-with-build-artifact-issuance run-build-artifact-process
                 require-build-artifacts! current-build-output-directory test-build-publication)
        (only-in "./source-closure.ss" for-each-build-module)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/expander current-expander-context make-top-context
                 current-expander-module-import core-import-module syntax-e
                 expander-context-id module-context-path)
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :clan/poo/object .o .ref .get .call)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/build unique-build-inputs)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-retained-source yuanxu-prepare-module-build-source call-with-module-compiler-inputs)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-read
                 module-source-name? module-source-admit-current! call-with-module-source-read-cache))
(export yuanxu-project-source-spec)
(def (project-native-make-specs entries package-prefix)
  ;; std/make names products using prefix + target, while gxc uses the
  ;; declared module identity. Keep those names identical for every target.
  (def groups (make-hash-table))
  (def order '())
  (for-each
    (lambda (entry)
      (def id (.get entry compiler-identity))
      (def name (build-target-name id package-prefix))
      (def full (symbol->string id))
      (def prefix
        (if (equal? full (if (string-empty? package-prefix) name
                            (string-append package-prefix "/" name)))
          #f
          (substring full 0 (- (string-length full) (string-length name) 1))))
      (unless (hash-key? groups prefix)
        (hash-put! groups prefix '())
        (set! order (cons prefix order)))
      (hash-update! groups prefix
        (cut cons `(gxc: ,name ,@(.get entry options)) <>) '())) entries)
  ;; The admitted cross-package prelude bootstraps independently of Core.
  (map (lambda (native-prefix)
         (.o prefix: native-prefix spec: (reverse (hash-ref groups native-prefix))))
       (append (filter identity (reverse order))
               (if (hash-key? groups #f) '(#f) '()))))
(def (build-target-name identity package-prefix)
  ;; One root-owned language file has an explicit native package identity.
  ;; Both call sites still verify its actual source path and prepared identity.
  (if (and (equal? package-prefix "yuanxu") (eq? identity 'tao3k/yuanxu/prelude))
    "prelude"
    (let ((name (symbol->string identity))
          (prefix (if (string-empty? package-prefix) "" (string-append package-prefix "/"))))
    (unless (string-prefix? prefix name)
      (error "compiler identity is outside the build package prefix" identity package-prefix))
    (let (relative (substring name (string-length prefix) (string-length name)))
      (unless (andmap module-source-name? (string-split relative #\/))
        (error "compiler identity is not a relative build target" identity))
      relative))))
(def (retained-build-entries specs root package-prefix selected current!)
  (unless (and (list? specs) (or (null? specs) (and (string? root) (path-absolute? root))))
    (error "retained build entries require a source root" root))
  (let ((seen (make-hash-table-eq)) (selected-by-path (make-hash-table)))
    ;; Resolve each selected path once. Retained libraries overlap the Module
    ;; projection; a scan per library repeated both POO reads and normalization.
    (for-each
      (lambda (entry)
        (hash-put! selected-by-path (path-normalize (.ref entry 'path)) entry))
      selected)
    (map
     (lambda (spec)
       (let* ((parts (if (string? spec) (list spec)
                        (if (and (pair? spec) (eq? (car spec) 'gxc:)) (cdr spec)
                            (error "retained entry must be a native Scheme target" spec))))
              (name (and (pair? parts) (car parts)))
              (options-value (and (pair? parts) (cdr parts))))
         (unless (and (string? name) (list? options-value) (andmap string? options-value)
                      (andmap module-source-name? (string-split name #\/))
                      (not (string-suffix? ".ss" name)))
           (error "invalid retained Scheme target" spec))
         ;; Check every unresolved component; normalization must not hide links.
         (def path-value
           (path-normalize
            (let walk ((directory root) (parts (string-split (string-append name ".ss") #\/)))
             (let (file (path-expand (car parts) directory))
               (unless (eq? (module-source-type file) (if (pair? (cdr parts)) 'directory 'regular))
                 (error "retained source is missing, non-regular or a symlink" file))
               (if (pair? (cdr parts)) (walk file (cdr parts)) file)))))
         (def old (hash-get selected-by-path path-value))
         (def prepared-input (if old (.ref old 'input)
                                 (yuanxu-prepare-module-retained-source path-value current!)))
         (def identity (.ref prepared-input 'compiler-identity))
         (unless (equal? name (build-target-name identity package-prefix))
           (error "retained source path and compiler identity disagree" name identity))
         (when (hash-key? seen identity)
           (error "duplicate retained compiler target" identity))
         (hash-put! seen identity #t)
         (when (and old (not (equal? options-value (.ref old 'options))))
           (error "conflicting retained compiler options" identity))
         (or old (.o kind: 'source path: path-value input: prepared-input options: options-value
                     compiler-identity: identity owner: 'build contributor: 'retained)))) specs)))
(def (merge-build-entries selected kept)
  (let ((seen (make-hash-table-eq)) (result '()))
    (for-each
     (lambda (entry)
       (let (id (.ref entry 'compiler-identity))
         (if (hash-key? seen id)
           (let (old (hash-ref seen id))
             (unless (and (equal? (.ref old 'path) (.ref entry 'path))
                          (equal? (.ref old 'options) (.ref entry 'options))
                          (equal? (.ref (.ref old 'input) 'compiler-forms)
                                  (.ref (.ref entry 'input) 'compiler-forms)))
               (error "conflicting compiler inputs" id)))
           (begin (hash-put! seen id entry) (set! result (cons entry result))))))
     (append selected kept))
    (reverse result)))

(def (yuanxu-project-source-spec source retained root entry-source demand: (demand #f))
  (if demand
    (project-test-source-spec source demand root entry-source)
    (project-selected-source-spec source retained root entry-source)))

;; Only the demanded test import closure is expanded. In particular this never
;; reads view.build-graph.entries, evaluates business scopes or scans test peers.
(def (project-test-source-spec view demand root entry-source)
  ((.ref demand 'admit-current))
  (def entry (yuanxu-prepare-module-retained-source entry-source void))
  (def package-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref entry 'compiler-identity)))))
  (def prefix (string-append package-prefix "/"))
  (def files (map path-normalize (.ref demand 'spec)))
  (def prepared (make-hash-table))
  (def observations (.ref entry 'source-inputs))
  (def entries '())
  (def (input! path)
    (def normalized (path-normalize path))
    (def input
      (or (hash-get prepared normalized)
          (let (value (yuanxu-prepare-module-retained-source normalized void))
            (hash-put! prepared normalized value)
            (set! observations (append (.ref value 'source-inputs) observations))
            value)))
    ((.ref input 'admit-current))
    input)
  ;; Derive each demanded package from the native header/package snapshot.
  ;; External selected owners keep their own identities; no catalog is scanned.
  (def packages (list (cons root package-prefix)))
  (for-each
    (lambda (file)
      (def input (input! file))
      (def metadata
        (find (lambda (row) (and (cdr row) (string=? (path-strip-directory (car row)) "gerbil.pkg")))
          (.ref input 'source-inputs)))
      (when metadata
       (let* ((directory (path-directory (car metadata)))
              (relative (substring file (string-length directory) (- (string-length file) 3)))
              (id (symbol->string (.ref input 'compiler-identity))))
        (unless (string-suffix? relative id)
          (error "test compiler identity has no package-relative source target" file id))
        (def namespace
          (path-strip-trailing-directory-separator
            (substring id 0 (- (string-length id) (string-length relative)))))
        (unless (assoc directory packages)
          (set! packages (cons (cons directory namespace) packages)))))) files)
  (def native-import (current-expander-module-import))
  (def (source-import path (reload? #f))
    (def datum (syntax-e path))
    (def name (and (symbol? datum) (symbol->string datum)))
    (def local
      (or
        (and name
          (ormap
            (lambda (package)
              (def prefix (string-append ":" (cdr package) "/"))
              (and (string-prefix? prefix name)
                (path-expand (string-append (substring name (string-length prefix)
                  (string-length name)) ".ss") (car package)))) packages))
        (and (equal? package-prefix "yuanxu") (eq? datum ':tao3k/yuanxu/prelude)
          (path-expand "prelude.ss" root))
        (and (string? datum) (path-absolute? datum) (string=? (path-extension datum) ".ss")
          (ormap (lambda (package) (string-prefix? (car package) datum)) packages) datum)))
    (if (and local (module-source-type local))
      (begin
        (when reload? (error "test imports require a fresh source epoch" local))
        (let* ((input (input! local)) (context (native-import local #f)))
          ((.ref input 'admit-current))
          context))
      (native-import path reload?)))
  (parameterize ((current-expander-context (make-top-context))
                 (current-expander-module-import source-import))
    (def seen (make-hash-table-eq))
    (for-each
      (lambda (file)
        (input! file)
        (for-each-build-module (core-import-module file)
          (lambda (context)
            (def id (expander-context-id context))
            (def name (and (symbol? id) (symbol->string id)))
            (def path (module-context-path context))
            (when (and (string? path) (eq? (module-source-type path) 'regular))
              (let (package
                (and name (find (lambda (entry)
                  (or (string-prefix? (string-append (cdr entry) "/") name)
                      (and (equal? (cdr entry) "yuanxu") (eq? id 'tao3k/yuanxu/prelude)))) packages)))
              (if (and package (string=? (path-extension path) ".ss"))
                (let* ((target (build-target-name id (cdr package)))
                       (expected (path-expand (string-append target ".ss") (car package)))
                       (input (input! expected)))
                  (unless (and (equal? (path-normalize path) (path-normalize expected))
                               (eq? id (.ref input 'compiler-identity)))
                    (error "test dependency does not match current package source" id path expected))
                  (unless (member (path-normalize expected) files)
                    ;; Native Make resolves BOTH sources and expected products
                    ;; from this projection's root/prefix. A nested gerbil.pkg
                    ;; may identify the source without changing that Make root.
                    ;; Absolute targets discard libdir during path-expand and
                    ;; make valid outputs appear missing on every warm run.
                    (let (make-target (build-target-name id package-prefix))
                      (unless (equal? (path-normalize expected)
                                      (path-normalize
                                        (path-expand (string-append make-target ".ss") root)))
                        (error "test dependency requires its package-owned native Make root" id expected root))
                      (set! entries
                        (cons (cons id make-target) entries)))))
                ;; Observe actual external interfaces, never their entire catalog.
                (when (member (path-extension path) '(".ss" ".ssi"))
                  (set! observations (cons (cons path (module-source-read path)) observations)))))))
          seen)) files))
  (def inputs (unique-build-inputs observations))
  (def (selected-graph!)
    (def selected (.ref view 'selected-graph))
    (unless (eq? selected (.ref demand 'selected-graph))
      (error "test demand belongs to another selected graph"))
    selected)
  (def (current!)
    ;; This source-only guard does not acquire the production build graph.
    ((.ref demand 'admit-current))
    (call-with-module-source-read-cache
      (lambda ()
        (hash-for-each (lambda (_path input) ((.ref input 'admit-current))) prepared)
        (module-source-admit-current! inputs))))
  (current!)
  (def publication (delay (test-build-publication projection)))
  (def endpoint
    (.o selected-graph: (selected-graph!) generation: (.ref (selected-graph!) 'generation)
        build-publication: (force publication)
        compiler-current: (lambda () (current!) (.call (force publication) .current))))
  (def projection
   (.o (:: projection)
      selected-graph: (selected-graph!) build-graph: endpoint demand-source: demand
      compiler-identities: (map car (reverse entries)) source-inputs: inputs
      source-root: root spec: (map (lambda (entry) `(gxc: ,(cdr entry))) (reverse entries))
      output-directory:
      (.get (force publication) artifact)
      compile-output: current-build-output-directory
      .compile: (lambda (libdir action) (call-with-build-artifact-issuance projection libdir action))
      admit-current: current!
      admit-artifacts: (lambda () (current!) (require-build-artifacts! endpoint) (current!))))
  projection)

(def (project-selected-source-spec source retained root entry-source)
  (when (current-module-build-phase?)
    (error "Module build phase cannot recursively project the root specification"))
  (unless (and (string? root) (path-absolute? root)
               (string? entry-source) (path-absolute? entry-source))
    (error "build projection requires absolute source and entry roots"))
  (def entry-input (yuanxu-prepare-module-build-source entry-source void))
  (def package-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref entry-input 'compiler-identity)))))
  (let* ((view (if (string? source) (yuanxu-load-modules source) source))
         (graph (.ref view 'build-graph))
         ;; Preparing retained headers only observes source and package metadata.
         ;; Share the existing pure read window across their Graph guards; end
         ;; it before native compilation or any independent freshness boundary.
         (kept (call-with-module-source-read-cache
                 (lambda ()
                   (retained-build-entries retained root package-prefix (.ref graph 'entries)
                     (lambda () ((.ref graph 'compiler-current)))))))
         ;; A selection may use Modules from another source package. Observe
         ;; their inputs and Graph guards below, but let that package's native
         ;; build own its output names and compiler options.
         (all-entries (merge-build-entries (.ref graph 'entries) kept))
         (entries
           (filter (lambda (entry)
                     (let (identity (.ref entry 'compiler-identity))
                       (or (and (equal? package-prefix "yuanxu")
                                (eq? identity 'tao3k/yuanxu/prelude))
                           (string-prefix? (string-append package-prefix "/")
                             (symbol->string identity))))) all-entries))
         (foreign? (not (= (length entries) (length all-entries))))
         (observed (unique-build-inputs
                     (append (.ref entry-input 'source-inputs) (.ref graph 'compiler-inputs)
                       (foldr append '()
                         (map (lambda (entry) (.ref (.ref entry 'input) 'source-inputs)) kept)))))
         (build-value
          (map (lambda (entry)
                 (let* ((name (build-target-name (.ref entry 'compiler-identity) package-prefix))
                        (expected (path-expand (string-append name ".ss") root)))
                   (unless (equal? (path-normalize expected) (path-normalize (.ref entry 'path)))
                     (error "source target does not match repository path" name (.ref entry 'path)))
                   `(gxc: ,name ,@(.ref entry 'options)))) entries)))
    (unless (null? (.ref graph 'other-projections))
      (error "direct source projection requires a dedicated consumer for generated contributions"))
    (def (current!)
      (call-with-module-source-read-cache
        (lambda ()
          ((.ref graph 'compiler-current))
          (for-each (lambda (entry) ((.ref (.ref entry 'input) 'admit-current))) kept)
          (module-source-admit-current! observed))))
    (def (publication-current!)
      (current!)
      ;; Output issuance covers the entire selected Graph. A package-only
      ;; compilation cannot certify outputs owned by its source dependencies.
      (when foreign?
        (error "selected Graph publication requires all package owners")))
    (current!)
    (.o (:: projection) selected-graph: (.ref graph 'selected-graph) build-graph: graph
        native-make-specs: (project-native-make-specs entries package-prefix)
        compiler-identities: (map (cut .ref <> 'compiler-identity) entries)
        source-inputs: observed
        ;; Ordinary package Make and issued compilation share role lowering,
        ;; not authority. A package build does not mint publication approval.
        .with-compiler-inputs:
        (lambda (action)
          (current!)
          (begin0 (call-with-module-compiler-inputs entries action) (current!)))
        .compile: (lambda (libdir action)
                    (publication-current!)
                    (call-with-build-artifact-issuance projection libdir
                      (lambda () (.call projection .with-compiler-inputs action))))
        .process: (lambda (libdir command)
                   (publication-current!)
                   (run-build-artifact-process projection libdir command))
        source-root: root spec: build-value admit-current: current!)))
