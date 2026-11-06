;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Project selected sources to ordinary std/build-script specifications.
;;; std/make owns compilation, dependency scheduling and clean.
(import (only-in :std/string/path path-absolute?)
        (only-in :gerbil/expander core-import-module expander-context-id)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module call-with-build-stage)
        (only-in :yuanxu/module-system/building/products build-output-directory
                 current-build-source-directory current-build-module-roots call-with-selected-output-lock
                 selected-output-source-directory artifact-files)
        (only-in :yuanxu/module-system/source/deferred-declaration module-entry-action)
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (runtime: :clan/poo/object)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/build unique-build-inputs module-test-source-spec retained-build-entries BuildSpecContract)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/module-system/source/preparation build-target-name yuanxu-prepare-module-retained-source yuanxu-prepare-module-build-source call-with-module-compiler-inputs)
        (only-in :yuanxu/module-system/source/admission module-source-type
                 module-source-name? module-source-admit-current! call-with-module-source-read-cache
                 module-source-measure-operation))
(export yuanxu-project-source-spec)
(def issue-build-artifacts
  (module-entry-action 'yuanxu/module-system/building/build-projection
    "yuanxu/module-system/building/artifacts"
    'yuanxu/module-system/building/artifacts#call-with-build-artifact-issuance))
(def process-build-artifacts
  (module-entry-action 'yuanxu/module-system/building/build-projection
    "yuanxu/module-system/building/artifacts"
    'yuanxu/module-system/building/artifacts#run-build-artifact-process))
(def (project-std-make-specs entries targets language compile?)
  ;; The package language is the only local target with a distinct prefix.
  ;; Gerbil orders dependencies within a batch. Its selected prerequisites
  ;; must be in the ordinary batch before the language target.
  (def prerequisites (make-hash-table-eq))
  (when compile?
    (for-each-build-module (core-import-module (.ref language 'path))
      (lambda (context) (hash-put! prerequisites (expander-context-id context) #t))))
  (def before '())
  (def after '())
  (def language-target #f)
  (for-each
    (lambda (entry target)
      (cond
       ((eq? (.ref entry 'compiler-identity) (.ref language 'compiler-identity))
        (set! language-target target))
       ((hash-key? prerequisites (.ref entry 'compiler-identity)) (set! before (cons target before)))
       (else (set! after (cons target after)))))
    entries targets)
  (def (ordinary targets)
    (let (batch-targets (reverse targets))
      (if (null? batch-targets) '() (list (.o prefix: #f spec: batch-targets)))))
  (def language-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref language 'compiler-identity)))))
  (unless language-target
    (error "package language is absent from admitted Make targets"
           (.ref language 'compiler-identity)))
  (let (language-spec (list language-target))
    (append (ordinary before) (list (.o prefix: language-prefix spec: language-spec)) (ordinary after))))

(def (collect-build-entries selected kept retained)
  (def seen (make-hash-table-eq))
  (def (first? entry)
    (def id (.ref entry 'compiler-identity))
    (cond
     ((hash-get seen id)
      => (lambda (old)
           (unless (and (equal? (.ref old 'path) (.ref entry 'path))
                        (equal? (.ref old 'options) (.ref entry 'options))
                        (equal? (.ref (.ref old 'input) 'compiler-forms)
                                (.ref (.ref entry 'input) 'compiler-forms)))
             (error "conflicting compiler inputs" id))
           #f))
     (else (hash-put! seen id entry) #t)))
  (def modules (filter first? selected))
  (def libraries (filter-map (lambda (entry target) (and (first? entry) (cons entry target)))
                            kept retained))
  (values modules libraries (hash-get seen 'tao3k/yuanxu/prelude)))

(def (yuanxu-project-source-spec source retained root entry-source demand: (demand #f))
  (if demand
    (module-test-source-spec source demand root entry-source retained)
    (project-selected-source-spec source retained root entry-source)))

(def (project-selected-source-spec source retained root entry-source)
  (when (current-module-build-phase?)
    (error "Module build phase cannot recursively project the root specification"))
  (when (ormap (lambda (target) (and (pair? target) (eq? (car target) exe:))) retained)
    (error "native programs require an explicit init-owned test demand"))
  (unless (and (string? root) (path-absolute? root)
               (string? entry-source) (path-absolute? entry-source))
    (error "build projection requires absolute source and entry roots"))
  (def entry-input
    (module-source-measure-operation 'build-entry-header
      (lambda () (yuanxu-prepare-module-build-source entry-source void))))
  (def package-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref entry-input 'compiler-identity)))))
  (def (local-entry? entry)
    (let (identity (.ref entry 'compiler-identity))
      (or (and (equal? package-prefix "yuanxu") (eq? identity 'tao3k/yuanxu/prelude))
          (string-prefix? (string-append package-prefix "/") (symbol->string identity)))))
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
         (retained-states (make-hash-table-eq))
         ;; Preparing retained headers only observes source and package metadata.
         ;; Share the existing pure read window across their own source guards.
         ;; The projection owns selected-Graph admission once per boundary; end
         ;; this window before compilation or independent currentness checks.
         (kept (module-source-measure-operation 'build-retained-entries
                 (lambda ()
                   (call-with-module-source-read-cache
                     (lambda ()
                       (retained-build-entries retained root package-prefix graph-entries
                     capture:
                     (lambda (value checker path ready? state)
                       ;; These procedures are captured at the native constructor,
                       ;; not read from an author-supplied object property.
                       (when state
                         (hash-put! retained-states (.ref value 'compiler-identity)
                           (lambda (input actual)
                             (and (eq? input value) (eq? actual checker) (state)))))
                       value)))))))
         ;; Graph entries are already admitted selected-owner SOURCE obligations.
         ;; A package prefix names a target; it cannot demote a selected source
         ;; to an installed prerequisite. Native imports outside this set remain
         ;; Gerbil prerequisites and never enter the compiler source view.
         ((values module-entries library-entries language)
          (collect-build-entries graph-entries kept retained))
         (entries (append module-entries (map car library-entries)))
         (foreign? (ormap (lambda (entry) (not (local-entry? entry))) entries))
         (observed (unique-build-inputs
                     (append (.ref entry-input 'source-inputs) (.ref graph 'compiler-inputs)
                       (foldr append '()
                         (map (lambda (entry) (.ref (.ref entry 'input) 'source-inputs)) kept)))))
         (module-value
          (map (lambda (entry)
                 (let* ((name (build-target-name (.ref entry 'compiler-identity)
                                (if foreign? "" package-prefix)))
                        (expected (path-expand (string-append name ".ss") root)))
                   ;; A local Make target must match the repository path. Cross-
                   ;; package targets use the existing checked source view; their
                   ;; original path/identity stays bound by input currentness.
                   (unless (or foreign?
                               (equal? (path-normalize expected) (path-normalize (.ref entry 'path))))
                     (error "source target does not match repository path" name (.ref entry 'path)))
                   `(gxc: ,name ,@(.ref entry 'options)))) module-entries))
         ;; Keep the package's original native targets/options. The only
         ;; overlap removal is an already checked identical selected target.
         (library-value
           (map (lambda (row)
                  (let (entry (car row))
                    (if foreign?
                      `(gxc: ,(build-target-name (.ref entry 'compiler-identity) "")
                             ,@(.ref entry 'options))
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
      (module-source-measure-operation 'build-spec-contract
        (lambda ()
          (validate BuildSpecContract (.o module-spec: module-value library-spec: library-value spec: value))))
      value)
    (def (with-admitted-spec receiver action)
      (current!)
      (admit-spec (.ref receiver 'spec))
      (begin0 (action)
        (current!)
        (admit-spec (.ref receiver 'spec))))
    (call-with-build-stage 'projection-current current!)
    (.o (:: projection) selected-graph: (.ref graph 'selected-graph) build-graph: graph
        ;; Prefix batches partition the exact admitted Make targets.
        .make-groups: (lambda (compile?)
                        (if (and language (not foreign?) (equal? package-prefix "yuanxu"))
                          (project-std-make-specs entries build-value language compile?)
                          '()))
        compiler-identities: (map (cut .ref <> 'compiler-identity) entries)
        ;; Installed imports are resolved by Gerbil, not manufactured from a
        ;; discarded foreign source partition. No selected identity lives here.
        dependency-identities: '()
        source-inputs: observed
        .admit-spec: admit-spec
        ;; Ordinary package Make and issued compilation share role lowering,
        ;; not authority. A package build does not mint publication approval.
        .with-compiler-inputs:
        (lambda (action (refuse-input-context #f))
          ;; Reject derived specs before a graph's state callback can run.
          (require-spec-identity! (.ref projection 'spec))
          (def source-state (compiler-source-state))
          (def (compile-inputs)
            (with-admitted-spec projection
              (lambda ()
                (call-with-module-compiler-inputs entries action unified?: foreign?
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
              (with-admitted-spec projection
                (lambda ()
                  (artifact-files (.ref projection 'compiler-identities) libdir #f)
                  ;; Unified Make targets need the same prefix-free directory.
                  (if foreign?
                    (let (directory (selected-output-source-directory libdir))
                      ;; std/build-script normalizes srcdir even for clean.
                      ;; Supply its empty output-owned directory, not role
                      ;; frames, source copies or another target manifest.
                      (create-directory* directory)
                      (parameterize ((current-build-source-directory directory))
                        (action)))
                    (action)))))))
        .compile: (lambda (libdir action)
                    (publication-current!)
                    (issue-build-artifacts
                      (list projection libdir
                        (lambda () (.call projection .with-compiler-inputs action)))))
        .process: (lambda (libdir command)
                   (publication-current!)
                   (process-build-artifacts (list projection libdir command)))
        source-root: root spec: build-value admit-current: current!)))
