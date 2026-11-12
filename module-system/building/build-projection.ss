;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Project selected sources to ordinary std/build-script specifications.
;;; std/make owns compilation, dependency scheduling and clean.
(import (only-in :std/string/path path-absolute?)
        (only-in :tao3k/yuanxu/module-system/building/source-package package-prelude-identity)
        (only-in :tao3k/yuanxu/module-system/building/program-publication project-program-init)
        (only-in :gerbil/expander core-import-module core-resolve-library-module-path
                 expander-context-id module-context-path import-module current-expander-compiling?)
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module call-with-build-stage package-library-spec/source-context)
        (only-in :tao3k/yuanxu/module-system/building/products build-output-directory
                 current-build-source-directory current-build-module-roots call-with-selected-output-lock
                 selected-output-source-directory artifact-files clean-build-artifacts!)
        (only-in :tao3k/yuanxu/module-system/source/deferred-declaration module-entry-action)
        (only-in :tao3k/yuanxu/module-system/source/declaration current-module-build-phase?)
        (runtime: :clan/poo/object)
        (only-in :tao3k/yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :tao3k/yuanxu/module-system/source/build unique-build-inputs module-test-source-spec retained-build-entries BuildSpecContract)
        (only-in :clan/poo/mop validate)
        (only-in :tao3k/yuanxu/module-system/source/preparation build-target-name yuanxu-prepare-module-retained-source yuanxu-prepare-module-build-source
                 call-with-module-compiler-inputs call-with-module-compiler-input-bindings)
        (only-in :tao3k/yuanxu/module-system/source/admission module-source-type
                 module-source-name? module-source-admit-current! call-with-module-source-read-cache
                 module-source-measure-operation))
(export yuanxu-project-source-spec)
(def issue-build-artifacts
  (module-entry-action 'tao3k/yuanxu/module-system/building/build-projection
    "tao3k/yuanxu/module-system/building/artifacts"
    'tao3k/yuanxu/module-system/building/artifacts#call-with-build-artifact-issuance))
(def process-build-artifacts
  (module-entry-action 'tao3k/yuanxu/module-system/building/build-projection
    "tao3k/yuanxu/module-system/building/artifacts"
    'tao3k/yuanxu/module-system/building/artifacts#run-build-artifact-process))
(def (collect-build-entries selected kept retained library-source?)
  (def sources (make-hash-table-eq))
  (def libraries-seen (make-hash-table-eq))
  (def (first? entry (selected? #f))
    (def id (.ref entry 'compiler-identity))
    (cond
     ((hash-get sources id)
      => (lambda (old)
           (unless (and (equal? (.ref old 'path) (.ref entry 'path))
                        (equal? (.ref (.ref old 'input) 'compiler-forms)
                                (.ref (.ref entry 'input) 'compiler-forms)))
             (error "conflicting compiler inputs" id))))
     (else (hash-put! sources id entry)))
    ;; Compiler identity authenticates source, not product or compiler options.
    ;; EXE options belong to its binary; a library retains its own options.
    (if (or (and (.slot? entry 'make-kind) (eq? (.ref entry 'make-kind) exe:))
            (and selected? (not (library-source? entry))))
      #t
      (cond
       ((hash-get libraries-seen id)
        => (lambda (old)
             (unless (equal? (.ref old 'options) (.ref entry 'options))
               (error "conflicting compiler inputs" id))
             #f))
       (else (hash-put! libraries-seen id entry) #t))))
  (def modules (filter (lambda (entry) (first? entry #t)) selected))
  (def libraries
    (filter-map
      (lambda (entry target) (and (first? entry) (cons entry target)))
      kept retained))
  (values modules libraries))

(def (yuanxu-project-source-spec source retained root entry-source demand: (demand #f))
  (if demand
    (module-test-source-spec source demand root entry-source retained)
    (project-selected-source-spec source retained root entry-source)))

(def (project-selected-source-spec source retained root entry-source)
  (when (current-module-build-phase?)
    (error "Module build phase cannot recursively project the root specification"))
  (unless (and (string? root) (path-absolute? root)
               (string? entry-source) (path-absolute? entry-source))
    (error "build projection requires absolute source and entry roots"))
  (def entry-input
    (module-source-measure-operation 'build-entry-header
      (lambda () (yuanxu-prepare-module-build-source entry-source void))))
  (def package-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref entry-input 'compiler-identity)))))
  (def identity-prefix (string-append package-prefix "/"))
  (def language (package-prelude-identity root))
  ;; A separately named language needs this ownership check. The ordinary
  ;; package prelude is already part of the package's retained libraries.
  (def owned-prelude
    (and language (not (string-prefix? identity-prefix (symbol->string language)))
         (path-normalize (path-expand "prelude.ss" root))))
  (def (package-prelude-entry? entry)
    (and owned-prelude (equal? (.ref entry 'path) owned-prelude)
         (eq? (.ref entry 'compiler-identity) language)))
  (def (local-entry? entry)
    (or (package-prelude-entry? entry)
        (string-prefix? identity-prefix
                        (symbol->string (.ref entry 'compiler-identity)))))
  (let* ((view (if (string? source) (yuanxu-load-modules source) source))
         (graph (module-source-measure-operation 'build-selected-graph
                  (lambda ()
                    (call-with-build-stage 'build-selected-graph
                      (lambda ()
                        (let (roots (current-build-module-roots))
                          (if roots
                            ((.ref view '.build-graph-for) roots)
                            (.ref view 'build-graph))))))))
         (graph-entries (.ref graph 'entries))
         (module-roots
          (map (lambda (entry)
                 (path-directory (.ref entry 'path)))
               (filter (lambda (entry) (eq? (.ref entry 'kind) 'publication)) graph-entries)))
         (init-source
          (and (.slot? view 'context) (.ref (.ref view 'context) 'init-source)))
         (output-prefix
          (string-append (path-strip-trailing-directory-separator
                           (path-normalize (path-expand (build-output-directory)))) "/"))
         (installed-libraries (make-hash-table-eq))
         (installed-library?
          (lambda (entry)
            (def id (.ref entry 'compiler-identity))
            (def name (string->symbol (string-append ":" (symbol->string id))))
            (def resolved
              (with-catch (lambda (failure) (if (syntax-error? failure) #f (raise failure)))
                (lambda () (core-resolve-library-module-path name))))
            (and (string? resolved) (string=? (path-extension resolved) ".ssi")
                 (not (string-prefix? output-prefix resolved))
                 (begin (hash-put! installed-libraries id #t) #t))))
         (module-source?
          (lambda (entry)
            (def path (.ref entry 'path))
            (or (null? module-roots) (equal? path init-source)
                (package-prelude-entry? entry)
                (ormap (lambda (directory) (string-prefix? directory path)) module-roots)
                ;; Gerbil resolves package libraries imported by foreign roles.
                ;; Products in this consumer's output still need their source
                ;; targets for hot builds and clean.
                (and (not (local-entry? entry)) (not (installed-library? entry))))))
         (native-target-index
          (and (.slot? graph 'std-make-targets)
            (let (index (make-hash-table))
              (for-each
                (lambda (row)
                  (hash-put! index (car row) (cons (cdr row) (hash-ref index (car row) '()))))
                (.ref graph 'std-make-targets))
              index)))
         ;; Native imports and the retained package closure own the targets.
         ;; Lower a reached yuanxu! declaration below; do not manufacture a
         ;; target merely because this selection was obtained from init.
         (retained-states (make-hash-table-eq))
         ;; Preparing retained headers only observes source and package metadata.
         ;; Share the existing pure read window across their own source guards.
         ;; The projection owns selected-Graph admission once per boundary; end
         ;; this window before compilation or independent currentness checks.
         (capture-retained
          (lambda (value checker path ready? state)
            (when state
              (hash-put! retained-states (.ref value 'compiler-identity)
                (lambda (input actual)
                  (and (eq? input value) (eq? actual checker) (state)))))
            value))
         (kept (module-source-measure-operation 'build-retained-entries
                 (lambda ()
                   (call-with-module-source-read-cache
                     (lambda ()
                       (retained-build-entries retained root package-prefix graph-entries
                         programs?: #t capture: capture-retained))))))
         ;; Expand actual native imports once. Keep explicit source objects and
         ;; their constructor-issued state; only missing dependencies need new
         ;; inputs, and no source-state procedure comes from an author field.
         (additional-spec
          (let* ((names (map (lambda (target) (if (string? target) target (cadr target))) retained))
                 (source-prefix
                   (string-append (path-strip-trailing-directory-separator (path-normalize root)) "/"))
                 (closure
                  (package-library-spec/source-context root (string->symbol package-prefix)
                    (map (lambda (name) (string-append name ".ss")) names) void
                    (lambda (context)
                      (let (path (module-context-path context))
                        (and (string? path) (string=? (path-extension path) ".ss")
                             (string-prefix? source-prefix (path-normalize path)) context))))))
            (filter (lambda (name) (not (member name names))) closure)))
         (retained (append additional-spec retained))
         (kept
          (append
            (retained-build-entries additional-spec root package-prefix graph-entries
              programs?: #t capture: capture-retained)
            kept))
         (kept (map (lambda (entry) (project-program-init view graph entry)) kept))
         ;; A declared package library may itself reach init. Project that
         ;; same native owner once, regardless of which edge discovered it.
         (graph-entries (map (lambda (entry) (project-program-init view graph entry)) graph-entries))
         (selected-entries (filter module-source? graph-entries))
         ((values module-entries library-entries)
          (collect-build-entries selected-entries kept retained
            (lambda (entry)
              (or (not native-target-index)
                  (ormap (lambda (target) (or (string? target) (eq? (car target) gxc:)))
                         (hash-ref native-target-index (.ref entry 'path) '()))))))
         (target-entries (append module-entries (map car library-entries)))
         (entries
           (let (seen (make-hash-table-eq))
             (filter (lambda (entry)
                       (def id (.ref entry 'compiler-identity))
                       (and (not (hash-key? seen id))
                            (begin (hash-put! seen id #t) #t))) target-entries)))
         (compiler-input-entries
          (let (seen (make-hash-table-eq))
            (filter (lambda (entry)
                      (def id (.ref entry 'compiler-identity))
                      (and (not (hash-key? seen id))
                           ;; The graph still observes the prerequisite's
                           ;; original source. Leave its native binding intact.
                           (not (hash-key? installed-libraries id))
                           (begin (hash-put! seen id #t) #t)))
                    (append graph-entries kept))))
         (native-init-entries
          (filter (lambda (entry) (eq? (.ref entry 'kind) 'init-publication)) entries))
         (foreign? (ormap (lambda (entry) (not (local-entry? entry))) entries))
         (observed (unique-build-inputs
                     (append (.ref entry-input 'source-inputs) (.ref graph 'compiler-inputs)
                       (foldr append '()
                         (map (lambda (entry) (.ref (.ref entry 'input) 'source-inputs)) kept)))))
         (module-value
          (foldr append '() (map (lambda (entry)
                 (let* ((name (if foreign?
                                (symbol->string (.ref entry 'compiler-identity))
                                (build-target-name (.ref entry 'compiler-identity) package-prefix language)))
                        (expected (path-expand (string-append name ".ss") root)))
                   ;; A multi-package projection uses native compiler identities
                   ;; in its owned prefix-free source view. Absolute author paths
                   ;; cannot predict native Make output locations correctly.
                   (unless (or foreign?
                               (equal? (path-normalize expected) (path-normalize (.ref entry 'path))))
                     (error "source target does not match repository path" name (.ref entry 'path)))
                   (if native-target-index
                     (map
                       (lambda (row)
                         (def target row)
                         (if (string? target) name
                           `(,(car target) ,name ,@(cddr target))))
                       (reverse (hash-ref native-target-index (.ref entry 'path) '())))
                     (list `(gxc: ,name ,@(.ref entry 'options)))))) module-entries)))
         ;; Keep the package's original native targets/options. The only
         ;; overlap removal is an already checked identical selected target.
         (library-value
           (map (lambda (row)
                  (let (entry (car row))
                    (if foreign?
                      (let (target (cdr row))
                        `(,(if (pair? target) (car target) gxc:)
                          ,(symbol->string (.ref entry 'compiler-identity))
                          ,@(if (pair? target) (cddr target) (.ref entry 'options))))
                      (cdr row))))
                library-entries))
         (build-value (append module-value library-value)))
    (unless (null? (.ref graph 'other-projections))
      (error "direct source projection requires a dedicated consumer for generated contributions"))
    (def (compiler-source-state)
      ;; Native target rows and their source guards do not need the compiler's
      ;; input routing index. Capture selected routing only for compilation,
      ;; with the original input/checker identities and before the fresh guard.
      (module-source-measure-operation 'compiler-source-state
        (lambda ()
          (def selected-states (make-hash-table-eq))
          (for-each
            (lambda (entry)
              (when (eq? (.ref entry 'kind) 'source)
                (let* ((input (.ref entry 'input))
                       (state ((.ref graph '.source-input-state) input))
                       (checker (.ref input 'admit-current)))
                  (when state
                    (hash-put! selected-states (.ref entry 'compiler-identity)
                      (lambda (value actual)
                        (and (eq? value input) (eq? checker actual) (state))))))))
            graph-entries)
          (lambda (input actual identity)
            (let (state (or (hash-get retained-states identity)
                            (hash-get selected-states identity)))
              (and state (state input actual)))))))
    (def (current!)
      (module-source-measure-operation 'build-current
        (lambda ()
          (call-with-module-source-read-cache
            (lambda ()
              ((.ref graph 'compiler-current))
              (for-each (lambda (entry) ((.ref (.ref entry 'input) 'admit-current))) kept)
              (module-source-admit-current! observed))))))
    (def (publication-current!)
      (current!)
      ;; Output issuance covers the entire selected Graph. Ordinary selected
      ;; compilation does not yet implement the cross-owner issuance obligations.
      (when foreign?
        (error "selected Graph publication requires all package owners")))
    (def (require-spec-identity! value)
      (unless (eq? value build-value)
        (error "build specification differs from the init-owned Make targets")))
    (def (admit-spec value)
      ;; Every use checks the actual native value against this init's two
      ;; independently produced inputs. This is not a cached admission verdict.
      (require-spec-identity! value)
      (validate BuildSpecContract
        (.o module-spec: module-value retained-spec: library-value spec: value))
      value)
    (def (with-admitted-spec receiver action)
      (current!)
      (admit-spec (.ref receiver 'spec))
      (begin0 (action)
        (current!)
        (admit-spec (.ref receiver 'spec))))
    (call-with-build-stage 'projection-current current!)
    (.o (:: projection) selected-graph: (.ref graph 'selected-graph) build-graph: graph
        compiler-identities: (map (cut .ref <> 'compiler-identity) entries)
        ;; Sources outside the selected Module roots remain observed compiler
        ;; dependencies; ordinary Core libraries have their own package list.
        dependency-identities:
        (filter (lambda (id) (not (memq id (.ref projection 'compiler-identities))))
          (map (cut .ref <> 'compiler-identity) compiler-input-entries))
        source-inputs: observed
        .admit-spec: admit-spec
        .prepare-compiler-contexts:
        (lambda ()
          (require-spec-identity! (.ref projection 'spec))
          (if (null? native-init-entries)
            (current!)
            (with-admitted-spec projection
              (lambda ()
                (call-with-module-compiler-input-bindings compiler-input-entries
                  (lambda ()
                    ;; Reload in Gerbil's actual dependency order. Reloading
                    ;; only init leaves cached consumers pointing at its OLD
                    ;; context, so native linking misses the generated imports.
                    (def owned (make-hash-table))
                    (def seen (make-hash-table-eq))
                    (def paths '())
                    (for-each (lambda (entry) (hash-put! owned (.ref entry 'path) #t)) entries)
                    (for-each
                      (lambda (entry)
                        (for-each-build-module (core-import-module (.ref entry 'path))
                          (lambda (context)
                            (def path (module-context-path context))
                            (when (and (string? path) (hash-get owned path))
                              (hash-remove! owned path)
                              (set! paths (cons path paths)))) seen)) entries)
                    (parameterize ((current-expander-compiling? #t))
                      (for-each (lambda (path) (import-module path #t #f))
                        (reverse paths))))
                  source-owner: graph)))))
        ;; Ordinary package Make and issued compilation share role lowering,
        ;; not authority. A package build does not mint publication approval.
        .with-compiler-inputs:
        (lambda (action (refuse-input-context #f) (record-selected-view? #f))
          ;; Reject derived specs before a graph's state callback can run.
          (require-spec-identity! (.ref projection 'spec))
          (def source-state (compiler-source-state))
          (def (compile-inputs)
            (with-admitted-spec projection
              (lambda ()
                (call-with-module-compiler-inputs compiler-input-entries action unified?: foreign?
                      recorded-entries:
                      (append
                        (filter (lambda (entry) (eq? (.ref entry 'kind) 'init-publication)) entries)
                        (if (and record-selected-view? (not foreign?) (equal? package-prefix "tao3k/yuanxu"))
                          module-entries '()))
                      source-reads: (.ref graph '.with-compiler-source-reads)
                      source-import: (.ref graph '.with-compiler-source-import)
                      source-state: source-state source-owner: graph
                      refuse-input-context: refuse-input-context))))
          (if foreign? (compile-inputs)
            (call-with-selected-output-lock (build-output-directory) compile-inputs)))
        .with-clean-outputs:
        (lambda (action)
          (require-spec-identity! (.ref projection 'spec))
          (def libdir (build-output-directory))
          (call-with-selected-output-lock libdir
            (lambda ()
              (def identities (.ref projection 'compiler-identities))
              (begin0
                (with-admitted-spec projection
                  (lambda ()
                    (artifact-files identities libdir #f)
                    ;; Unified Make targets need the same prefix-free directory.
                    (if foreign?
                      (let (directory (selected-output-source-directory libdir))
                        (create-directory* directory)
                        (parameterize ((current-build-source-directory directory))
                          (action)))
                      (action))))
                ;; STD Make cleans its declared outputs. A selected source
                ;; environment also owns the remaining dynamic generations.
                (when foreign? (clean-build-artifacts! identities libdir))))))
        .compile: (lambda (libdir action)
                    (publication-current!)
                    (issue-build-artifacts
                      (list projection libdir
                        (lambda () (.call projection .with-compiler-inputs action)))))
        .process: (lambda (libdir command)
                   (publication-current!)
                   (process-build-artifacts (list projection libdir command)))
        source-root: root spec: build-value admit-current: current!)))
