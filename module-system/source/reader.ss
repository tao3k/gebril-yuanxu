;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Trusted build-time declaration evaluation using the native expander. This
;;; neither compiles selected roots nor invokes their deferred core.link scopes.
(import (only-in :core/configuration/json current-configuration-input-observer)
        (only-in :core/ops/progress execution-progress!)
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/expander current-expander-context make-top-context
                 current-expander-module-import eval-syntax expander-context-id module-context-path
                 core-resolve-library-module-path module-context-code module-context?
                 current-expander-compile current-expander-eval current-expander-phi
                 expander-context-table module-context-import)
        (only-in :clan/poo/object .o .cc .ref .slot?)
        :core/module-system/source/admission
        :core/module-system/source/preparation
        (only-in :core/module-system/source/declaration current-module-build-resolver)
        :core/module-system/source/objects
        (only-in :core/module-system/building/source-closure for-each-build-module poo-flow-core-bootstrap-contexts
                 poo-flow-core-bootstrap-source-path))
(export module-publication-reader module-prepared-source-binding)
(def (reader-evaluation-observers owned completed)
  ;; SDK runtime imports bypass current-expander-module-eval. Pair the exact
  ;; phi-zero module body with its compiled program, then observe successful
  ;; evaluation of that same program. Macro-phase or partial evaluation alone
  ;; grants no release capability. Delegate all SDK results without alteration.
  (def native-compile (current-expander-compile))
  (def native-eval (current-expander-eval))
  (def pending (make-hash-table-eq))
  (def (body-event stage context)
    (let (observer (current-module-source-observer))
      (when observer
        (observer stage 1)
        ;; Only interface bodies receive phase snapshots. Other private bodies
        ;; contribute scalar work counts without sampling once per dependency.
        (when (string-suffix? "-interface.ss" (module-context-path context))
          (observer
            (list 'reader-declaration
              (cons 'bindings (hash-length (expander-context-table context)))
              (cons 'imports (length (module-context-import context)))) 1)))))
  (def (owned-body? context form)
    (and (module-context? context) (zero? (current-expander-phi))
         (eq? form (module-context-code context))
         (string? (module-context-path context))
         (hash-key? owned (path-normalize (module-context-path context)))))
  (def (compile form)
    (let* ((context (current-expander-context))
           (owned? (owned-body? context form)))
      (when owned? (body-event 'reader-body-expanded context))
      (let (program (native-compile form))
        (when (and (pair? program) owned?)
          (body-event 'reader-body-compiled context)
          (hash-put! pending program (cons context form)))
        program)))
  (def (evaluate program)
    (let (entry (hash-get pending program))
      (call-with-values (lambda () (native-eval program))
        (lambda results
          (when entry
            (hash-remove! pending program)
            (hash-put! completed (car entry) (cdr entry))
            (body-event 'reader-body-evaluated (car entry)))
          (apply values results)))))
  (values compile evaluate))
(def (release-reader-expansions! completed)
  ;; Only Core-generated interpreter wrappers occur in this completed set.
  ;; They are never compiler inputs: building projects the guarded originals.
  ;; Keep the context, imports, bindings, phases and runtime promise intact.
  ;; In particular, do not import an unused wrapper merely to find a context.
  (def released 0)
  (hash-for-each
    (lambda (context code)
      (when (and code (eq? code (module-context-code context)))
        (slot-set! context 'code #f)
        (set! released (+ released 1)))) completed)
  (when (current-module-source-observer)
    ((current-module-source-observer)
      (list 'reader-lifetime (cons 'completed (hash-length completed))
                             (cons 'released released)) 1))
  (hash-clear! completed))
(def (remove-reader-tree path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-reader-tree (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (reader-body forms)
  ;; Preparation owns these native compiler headers; preserve its prelude while
  ;; assigning a fresh private identity to this interpreter-only projection.
  (let loop ((tail forms) (prelude '()))
    (cond
     ((and (pair? tail) (eq? (car tail) 'prelude:))
      (loop (cddr tail) (list (car tail) (cadr tail))))
     ((and (pair? tail) (memq (car tail) '(package: namespace:)))
      (loop (cddr tail) prelude))
     (else (append prelude tail)))))
(def compiler-core-root (path-normalize (path-expand "../.." (path-directory (this-source-file)))))
;; One canonical-library check for publication and configuration readers. This
;; prepares observations, never imports, expands or initializes the dependency.
(def (public-dependency-input path)
  (let* ((input (with-catch (lambda (_error) #f)
                  (lambda () (poo-flow-prepare-module-tool-source path void))))
         (identity (and input (.ref input 'compiler-identity)))
         (external? (and (symbol? identity)
                         (not (string-prefix? "core/" (symbol->string identity)))))
         (resolved
          (and external?
            (with-catch (lambda (_error) #f)
              (lambda ()
                (core-resolve-library-module-path
                  (string->symbol (string-append ":" (symbol->string identity)))))))))
    (and (string? resolved) (equal? (path-normalize path) (path-normalize resolved)) input)))
;; Check the demanded SDK dependency subgraph, not every selected role on each
;; import edge. Complete role/asset guards still bracket expansion/evaluation.
(def (admit-compiler-inputs! context inputs-for (visit (lambda (_input) (void))))
  (call-with-module-source-read-cache
    (lambda ()
      (for-each
        (lambda (input)
          (module-source-admit-current! (.ref input 'source-inputs))
          (visit input))
        (inputs-for context)))))
;; Preparation is determined by an actual SDK context and its observed source.
;; Keep the projection, never an admission result. Every reuse checks bytes and
;; native package identity again; changed code needs a fresh compiler context.
(def compiler-tool-inputs (make-hash-table-eq weak-keys: #t))
(def (compiler-tool-input context path)
  (let* ((normalized (path-normalize path))
         (previous (hash-get compiler-tool-inputs context)))
    (if previous
      (begin
        (unless (equal? normalized (car previous))
          (error "compiler tool source path changed" path))
        ((.ref (cdr previous) 'admit-current))
        (cdr previous))
      (let (input (poo-flow-prepare-module-tool-source path void))
        (unless (eq? (expander-context-id context) (.ref input 'compiler-identity))
          (error "compiler tool source identity mismatch" (expander-context-id context) path))
        (hash-put! compiler-tool-inputs context (cons normalized input))
        input))))
(def (module-compiler-tools)
  (def tool-contexts (poo-flow-core-bootstrap-contexts))
  (def tool-paths (make-hash-table))
  (def tool-inputs (make-hash-table-eq))
  (def tool-observations (make-hash-table))
  (def dependency-index (make-hash-table-eq))
  (def (inputs-for context)
    ;; Cache only the immutable SDK import graph for this reader snapshot.
    ;; Every caller above still checks the actual source observations; no
    ;; acceptance or initializer result is stored in this structural index.
    (when (current-module-source-observer)
      ((current-module-source-observer) 'compiler-closure-requests 1)
      ((current-module-source-observer) (list 'compiler-demand context) 1))
    (if (hash-key? dependency-index context)
      (hash-ref dependency-index context)
      (let (inputs '())
        (when (current-module-source-observer)
          ((current-module-source-observer) 'compiler-closure-walks 1))
        (for-each-build-module context
          (lambda (child)
            (let (input (hash-get tool-inputs child))
              (when input
                (when (current-module-source-observer)
                  ((current-module-source-observer)
                    (list 'compiler-discovery context child (.ref input 'path)) 1))
                (set! inputs (cons input inputs))))))
        (let (ordered (reverse inputs))
          (hash-put! dependency-index context ordered)
          ordered))))
  ;; Reuse only exact SDK-observed compiler contexts. A source path or Core-like
  ;; identity alone grants no exemption from publication source confinement.
  (parameterize ((current-module-source-phase 'compiler-tools))
   (call-with-module-source-read-cache
    (lambda ()
      (for-each
        (lambda (entry)
          (let* ((id (car entry)) (context (cdr entry))
                 (native-path (module-context-path context))
                 (path (if (and (string? native-path) (string=? (path-extension native-path) ".ss"))
                         native-path
                         (poo-flow-core-bootstrap-source-path context compiler-core-root))))
            (when (and (symbol? id) (string-prefix? "core/" (symbol->string id))
                       (string? path) (string=? (path-extension path) ".ss"))
              (let (input (compiler-tool-input context path))
                (unless (eq? id (.ref input 'compiler-identity))
                  (error "compiler tool source identity mismatch" id path))
                (hash-put! tool-paths (path-normalize path) context)
                (hash-put! tool-inputs context input)
                (for-each
                  (lambda (observation)
                    (let (file (car observation))
                      (when (and (hash-key? tool-observations file)
                                 (not (equal? (hash-ref tool-observations file) (cdr observation))))
                        (error "inconsistent compiler tool source observations" file))
                      (hash-put! tool-observations file (cdr observation))))
                  (.ref input 'source-inputs))))))
        (hash->list tool-contexts)))))
  (values tool-contexts tool-paths inputs-for tool-observations))
(def (module-publication-reader)
  (let ((guards '()) (dependencies (make-hash-table)) (refused? #f)
        (kernel-contexts (make-hash-table)) (kernel-inputs (make-hash-table-eq))
        (kernel-closures (make-hash-table-eq))
        (preparations (make-hash-table)))
    ;; Reuse inert role/header projections within this reader's source epoch.
    ;; current! below checks the retained byte/package guards before EVERY use.
    ;; This does not retain an evaluated publication or skip macro/initializer
    ;; execution. Fresh SourceRef provenance is attached to the returned view.
    (def (preparation-key source)
      (unless (poo-flow-module-source-ref? source)
        (error "publication preparation requires a SourceRef" source))
      (let (metadata (poo-flow-module-source-ref-metadata source))
        (cons (poo-flow-module-source-ref-kind source)
                    (cons (path-normalize (poo-flow-module-source-ref-value source))
                      (map (lambda (name) (assq name metadata))
                           '(module-id module-root module-tree-root))))))
    (def (prepare-publication source)
      (let* ((key (preparation-key source))
             (previous (hash-get preparations key)))
        (when (current-module-source-observer)
          ((current-module-source-observer) 'publication-preparation-requests 1))
        (if previous
          (begin (check-preparation-policy! previous) (.cc previous 'source source))
          (let (value
                 (begin
                   (when (current-module-source-observer)
                     ((current-module-source-observer) 'publication-policy-checks 1))
                   (poo-flow-prepare-module-publication source)))
            (when (current-module-source-observer)
              ((current-module-source-observer) 'publication-preparation-walks 1))
            (hash-put! preparations key value)
            value))))
    (def (check-preparation-policy! prepared)
      ;; Never cache authoring admission: MOP policy objects may change without
      ;; changing source bytes. Recheck the actual policy before using syntax.
      (let* ((source (.ref prepared 'source))
             (metadata (poo-flow-module-source-ref-metadata source))
             (owner (cdr (assq 'module-id metadata)))
             (root (cdr (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
             (policy poo-flow-default-module-style-policy))
        (when (current-module-source-observer)
          ((current-module-source-observer) 'publication-policy-checks 1))
        ((.ref policy 'validate) policy owner root module-source-read)
        ;; A policy is an author-code boundary, not a source-cache window.
        ((.ref prepared 'admit-current))))
    ;; Cache only completed SDK context topology. Input registration can grow
    ;; during declaration imports, so resolve kernel-inputs afresh on EVERY use.
    ;; Neither source-check results nor macro/initializer effects enter this cache.
    (def (kernel-closure context)
      (when (current-module-source-observer)
        ((current-module-source-observer) 'kernel-closure-requests 1))
      (if (hash-key? kernel-closures context) (hash-ref kernel-closures context)
        (let (children '())
          (when (current-module-source-observer)
            ((current-module-source-observer) 'kernel-closure-walks 1))
          (for-each-build-module context
            (lambda (child) (set! children (cons child children))))
          (let (ordered (reverse children))
            (hash-put! kernel-closures context ordered) ordered))))
    (defvalues (tool-contexts tool-paths tool-dependencies tool-observations)
      (module-compiler-tools))
    (def (check-current! observed-guards)
      (when (current-module-source-observer)
        ((current-module-source-observer) '(publication-guard-run) 1))
      (module-source-admit-current! (hash->list tool-observations)
                                    "compiler tool source changed; use a fresh reader")
      (for-each (lambda (guard) (module-source-observe guard)) observed-guards))
    (def (current!)
      (when refused? (error "build publication reader was refused"))
      ;; Recheck bytes/package observations once per reader boundary; repeatedly
      ;; reparsing every tool through every individual guard is quadratic work.
      (def (check!)
        (parameterize ((current-module-source-phase 'publication-current))
          (call-with-module-source-read-cache
           (lambda ()
             ;; A nested Graph/role guard can reach this reader many times in the
             ;; same pure check. Memoize that check, including byte comparisons,
             ;; only until the enclosing observation boundary ends. A newly added
             ;; source guard changes the key, even within that boundary.
             (module-source-observe check-current! guards)))))
      ;; Attribute the caller without changing the cache key or retaining a
      ;; result across its boundary. Brackets also close on a refused check.
      (let ((observer (current-module-source-observer))
            (origin (current-module-source-phase)))
        (if observer
          (dynamic-wind
            (lambda () (observer (list 'publication-guard-start origin) 1))
            check!
            (lambda () (observer (list 'publication-guard-end origin) 1)))
          (check!))))
    (def (read-publication source-value)
      (with-catch
       (lambda (exception) (set! refused? #t) (raise exception))
       (lambda ()
         (when (current-module-source-observer)
           ((current-module-source-observer)
             (list 'publication-start (poo-flow-module-source-ref-value source-value)) 1))
         (parameterize ((current-module-source-phase 'declaration-before)) (current!))
         (let* ((prepared (prepare-publication source-value))
                (interface-path (path-normalize (poo-flow-module-source-ref-value source-value)))
                (root (path-directory interface-path))
                (tree-row (assq 'collection-root (poo-flow-module-source-ref-metadata source-value)))
                (tree (and tree-row (path-normalize (cdr tree-row))))
                (source-tree-row (assq 'source-tree (poo-flow-module-source-ref-metadata source-value)))
                (source-tree (and source-tree-row (cdr source-tree-row)))
                (package-input (find (lambda (row) (and (cdr row) (string=? (path-strip-directory (car row)) "gerbil.pkg")))
                                     (.ref prepared 'source-inputs)))
                (package-root (and package-input (path-normalize (path-directory (car package-input)))))
                ;; Source authority comes from the owning directory Context,
                ;; independently of a nested compiler package/prelude boundary.
                (repository-root (and source-tree (.slot? source-tree 'kernel-root)
                                      (.ref source-tree 'kernel-root)))
                (kernel-root
                 (if (and repository-root tree
                          (string-prefix?
                            (string-append (path-strip-trailing-directory-separator repository-root) "/") tree))
                   repository-root package-root))
                (package-prefix
                 (and package-root
                      (let* ((relative (path-strip-extension (substring interface-path (string-length package-root) (string-length interface-path))))
                             (id (symbol->string (.ref prepared 'compiler-identity))))
                        (substring id 0 (- (string-length id) (string-length relative))))))
                (kernel-depth 0)
                (id-text (symbol->string (.ref prepared 'compiler-identity)))
                (id-prefix (substring id-text 0 (- (string-length id-text) (string-length "interface"))))
                (directory (make-temporary-file-name "publication-reader-"))
                (prefix (symbol->string (gensym 'publication-reader-)))
                (wrappers (make-hash-table)) (artifacts (make-hash-table))
                (completed (make-hash-table-eq))
                (input-values '()) (input-paths (make-hash-table)) (native-import (current-expander-module-import)))
           (defvalues (compile evaluate) (reader-evaluation-observers artifacts completed))
           (def (write-wrapper path forms)
             (let* ((name (string-append (number->string (hash-length wrappers)) "-" (path-strip-directory path)))
                    (target (path-expand name directory)))
               (call-with-output-file target
                 (lambda (port)
                   (write 'package: port) (display " " port) (write prefix port) (newline port)
                   (write 'namespace: port) (display " " port)
                   (write (string-append prefix "/" (path-strip-extension name)) port) (newline port)
                   (for-each (lambda (form) (write form port) (newline port)) forms)))
               (hash-put! artifacts (path-normalize target) #t)
               (hash-put! wrappers path target) target))
           (def (record-input! input)
             (let (path (.ref input 'path))
               (unless (hash-key? input-paths path)
                 (hash-put! input-paths path #t)
                 (set! input-values (cons input input-values)))))
           (def (record-data! file text)
             (def relative
               (let (prefix (string-append (path-strip-trailing-directory-separator root) "/"))
                 (unless (string-prefix? prefix file)
                   (error "configuration asset leaves its Module" file root))
                 (substring file (string-length prefix) (string-length file))))
             ;; No escaping directory symlinks, even when the final file is regular.
             (let walk ((directory root) (parts (string-split relative #\/)))
               (let (next (path-expand (car parts) directory))
                 (unless (eq? (module-source-type next) (if (pair? (cdr parts)) 'directory 'regular))
                   (error "configuration asset must be owner-confined and regular" file))
                 (when (pair? (cdr parts)) (walk next (cdr parts)))))
             (def observations (list (cons file (string-copy text))))
             (def (asset-current!)
               (module-source-admit-current! observations "selected configuration asset changed"))
             (asset-current!)
             (unless (hash-key? input-paths file)
               (set! guards (cons asset-current! guards))
               (record-input!
                 (.o kind: 'data path: file relative-path: relative
                     source-inputs: observations admit-current: asset-current!))))
           (def (within? directory path)
             (string-prefix? (string-append (path-strip-trailing-directory-separator directory) "/") path))
           (def (tool-context context reload?)
             (when reload? (error "compiler tool reload requires a fresh publication reader"))
             (unless (eq? context (hash-get tool-contexts (expander-context-id context)))
               (error "compiler tool context changed during publication"))
             ;; This walk is a pure source check, not expansion. Shared tool
             ;; ancestors must not reread the same bytes once per import edge.
             ;; End the observation scope before returning to native-import.
             (parameterize ((current-module-source-phase 'compiler-import))
               (admit-compiler-inputs! context tool-dependencies
                 (lambda (input)
                   ;; The explicit SDK bootstrap includes shared JSON artifact
                   ;; definitions beside the JSON Module. Directory ownership
                   ;; alone does not make those canonical libraries a role.
                   ;; Actual publication roles (including deferred Build) must
                   ;; never become implicit compiler capabilities.
                   (let (path (path-normalize (.ref input 'path)))
                     (when (or (equal? path interface-path)
                               (member path (.ref prepared 'role-sources))
                               (equal? path (.ref prepared 'build-source)))
                       (error "compiler tool cannot depend on Module implementation" path)))
                   ;; SDK tool sources remain guarded in tool-observations.
                   ;; Only this repository's sources become compiler entries;
                   ;; a contribution must not rebuild its installed Core SDK.
                   (when (and kernel-root (within? kernel-root (path-normalize (.ref input 'path))))
                     (record-input! input)))))
             context)
           (def (source-wrapper original-path allowed-root)
             (let (path (path-normalize original-path))
               (when (equal? path interface-path)
                 (error "publication bootstrap cannot import its own interface" interface-path))
               (or (hash-get wrappers path)
                   (let (input (poo-flow-prepare-module-private-source allowed-root original-path void))
                     (set! guards (cons (.ref input 'admit-current) guards))
                     (record-input! input)
                     (write-wrapper path (reader-body (.ref input 'compiler-forms)))))))
           (def (shared-context original-path owner-root reload? (shared? #t))
             (let* ((path (path-normalize original-path))
                    (context
                     (or (hash-get kernel-contexts path)
                         (let (target (source-wrapper original-path owner-root))
                           (dynamic-wind
                            (lambda () (when shared? (set! kernel-depth (+ kernel-depth 1))))
                            (lambda ()
                              (when (current-module-source-observer)
                                ((current-module-source-observer)
                                  (list 'native-source-import-start path) 1))
                              (let (context (native-import target reload?))
                                (execution-progress! (list 'source-import path) 1)
                                (when (current-module-source-observer)
                                  ((current-module-source-observer)
                                    (list 'native-source-import-end path
                                          (expander-context-id context)) 1))
                                (hash-put! kernel-contexts path context)
                                (hash-put! kernel-inputs context
                                  (find (lambda (input) (equal? (.ref input 'path) path)) input-values))
                                context))
                            (lambda () (when shared? (set! kernel-depth (- kernel-depth 1)))))))))
               (for-each
                 (lambda (child)
                   (let (input (hash-get kernel-inputs child))
                     (when input (record-input! input))))
                 (kernel-closure context))
               context))
           (def (source-context original-path reload?)
             (let (path (path-normalize original-path))
               (cond
                ((equal? path interface-path)
                 (error "publication bootstrap cannot import its own interface" interface-path))
                ((hash-get tool-paths path)
                 => (lambda (context) (tool-context context reload?)))
                ((within? root path)
                 (when (> kernel-depth 0) (error "shared source cannot depend on Module implementation" path))
                 (shared-context original-path root reload? #f))
                ((and source-tree ((.ref source-tree 'locate-owner) path))
                 => (lambda (owner) (shared-context original-path (.ref owner 'root) reload?)))
                ((and kernel-root tree (within? kernel-root path) (not (within? tree path))
                      (not (and source-tree (.slot? source-tree 'contains-module-path?)
                                ((.ref source-tree 'contains-module-path?) path))))
                 (shared-context original-path kernel-root reload?))
                (else
                 ;; Public dependencies may expand a relative source import
                 ;; before an SDK context has been cached. Reuse the canonical
                 ;; library only if its declared identity resolves to this exact
                 ;; source; a namespace label or arbitrary external path is not
                 ;; sufficient. Core sources still use the confined paths above.
                 (let (input (public-dependency-input path))
                   (unless input
                     (error "source import leaves its Module and package kernel" path))
                   (when reload? (error "public dependency reload requires a fresh environment"))
                   (set! guards (cons (.ref input 'admit-current) guards))
                   (parameterize ((current-expander-module-import native-import))
                     (native-import original-path #f)))))))
           (def (resolve-build!)
             (parameterize ((current-module-source-phase 'build-role-before)) (current!))
             (let* ((path (.ref prepared 'build-source))
                    (input (poo-flow-prepare-module-build-source path void))
                    (related (map (lambda (file)
                                    (poo-flow-prepare-module-build-source file void))
                                  (.ref prepared 'role-sources))))
               (let (value (module-prepared-source-binding input 'Build related role-imports?: #t
                 shared-contexts: kernel-contexts shared-inputs: kernel-inputs
                 private-sources: (filter (lambda (entry)
                   (and (not (and (.slot? entry 'kind) (eq? (.ref entry 'kind) 'data)))
                        ;; Reuse the exact admitted publication closure, including
                        ;; its kernel dependencies. Restricting this to owner roles
                        ;; loses their transitive imports once interception remains
                        ;; active. SDK tools retain their canonical checked contexts.
                        (not (hash-key? tool-paths (path-normalize (.ref entry 'path))))
                        (not (member (path-normalize (.ref entry 'path))
                                     (map path-normalize (.ref prepared 'role-sources))))))
                   input-values)))
                 (parameterize ((current-module-source-phase 'build-role-after)) (current!)) value)))
           (dynamic-wind
            (lambda () (create-directory directory))
            (lambda ()
              (for-each
                (lambda (path)
                  ;; The native import hook below already resolves a retained
                  ;; role context and projects its CURRENT dependency registry.
                  ;; Do not parse/write an unused wrapper for that same context.
                  (unless (hash-key? kernel-contexts (path-normalize path))
                    (source-wrapper (path-normalize path) root)))
                (.ref prepared 'role-sources))
              (set! guards (cons (.ref prepared 'admit-current) guards))
              (let (wrapper (write-wrapper interface-path (reader-body (.ref prepared 'reader-forms))))
                (parameterize
                    ((current-configuration-input-observer record-data!)
                     (current-expander-compile compile)
                     (current-expander-eval evaluate)
                     (current-expander-context (make-top-context))
                     (current-module-build-resolver resolve-build!)
                     (current-expander-module-import
                      (lambda (path (reload? #f))
                        (cond
                         ((and (string? path) (hash-key? artifacts (path-normalize path)))
                          (native-import path reload?))
                         ((and (string? path) (string=? (path-extension path) ".ss"))
                          (source-context path reload?))
                         (else
                          ;; Compiled libraries must retain their canonical SDK
                          ;; import closure. Redirect only the caller's source
                          ;; binding, never imports inside a compiled library.
                          (let* ((context (parameterize ((current-expander-module-import native-import))
                                            (native-import path reload?)))
                                 (identity (expander-context-id context))
                                 (id (and (symbol? identity) (symbol->string identity)))
                                 (native-path (module-context-path context))
                                 (owned-path (if (and (string? native-path)
                                                      (string=? (path-extension native-path) ".ss"))
                                               native-path
                                               (poo-flow-core-bootstrap-source-path context compiler-core-root)))
                                 (owner (and source-tree owned-path
                                             ((.ref source-tree 'locate-owner) owned-path))))
                            ;; Symbol and exact source-path imports share the same
                            ;; observed compiler-context and currentness boundary.
                            (cond
                             ((hash-key? tool-contexts identity) (tool-context context reload?))
                             (owner (source-context owned-path reload?))
                             ((and id (string-prefix? id-prefix id))
                              (source-context (path-expand (string-append (substring id (string-length id-prefix) (string-length id)) ".ss") root) reload?))
                             ((and id package-prefix (string-prefix? package-prefix id))
                              (source-context (path-expand (string-append (substring id (string-length package-prefix) (string-length id)) ".ss") package-root) reload?))
                             (else context))))))))
                  (eval-syntax `(import ,wrapper))
                  (let (value (eval-syntax (.ref prepared 'binding)))
                    (parameterize ((current-module-source-phase 'declaration-after)) (current!))
                    (release-reader-expansions! completed)
                    (when (current-module-source-observer)
                      ;; Counts describe this reader's actual retention roots;
                      ;; observers never receive the context/syntax objects.
                      ((current-module-source-observer)
                        (list 'reader-retention
                          (cons 'tools (hash-length tool-contexts))
                          (cons 'private-contexts (hash-length kernel-contexts))
                          (cons 'dependency-closures (hash-length kernel-closures))
                          (cons 'prepared-publications (hash-length preparations))
                          (cons 'source-objects (hash-length kernel-inputs))
                          (cons 'source-guards (length guards))) 1)
                      ((current-module-source-observer)
                        (list 'publication-end interface-path) 1))
                    ;; Include the already prepared roles as well as private
                    ;; dependencies. Build projection must not allocate a second
                    ;; header/guard object for the very same observed source.
                    (hash-put! dependencies interface-path (reverse input-values))
                    value))))
            (lambda () (remove-reader-tree directory)))))))
    (.o read: read-publication admit-current: current!
        preparation:
        (lambda (source)
          ;; Only a successfully observed declaration may supply this capability.
          ;; This is the same inert projection, not another publication reader.
          (current!)
          (unless (hash-key? dependencies (path-normalize (poo-flow-module-source-ref-value source)))
            (error "publication preparation requires a completed read"))
          (let (prepared (hash-get preparations (preparation-key source)))
            (unless prepared (error "publication preparation owner mismatch"))
            (check-preparation-policy! prepared)
            ;; Take the dependency registry at this consumption, not when the
            ;; inert preparation was cached. Both views share this one guard.
            (.cc prepared 'source source
              'source-dependencies
              (hash-ref dependencies (path-normalize (poo-flow-module-source-ref-value source))))))
        inputs: (lambda (source)
                  (parameterize ((current-module-source-phase 'publication-inputs)) (current!))
                  (hash-ref dependencies (path-normalize (poo-flow-module-source-ref-value source)))))))

;; Explicit build-tool role evaluation uses the same private native-wrapper
;; boundary as publication reading. It is not an import/Loader implementation.
(def (module-prepared-source-binding prepared binding (related '())
                                    role-imports?: (role-imports? #f)
                                    shared-contexts: (shared-contexts #f)
                                    shared-inputs: (shared-inputs #f)
                                    private-sources: (private-sources '()))
  (let* ((inputs (append (cons prepared related) private-sources))
         (directory (make-temporary-file-name "configuration-reader-"))
         (prefix (symbol->string (gensym 'configuration-reader-)))
         (wrappers (make-hash-table))
         (owned (make-hash-table)) (completed (make-hash-table-eq))
         (native-import (current-expander-module-import)))
    (defvalues (compile evaluate) (reader-evaluation-observers owned completed))
    (defvalues (tool-contexts tool-paths tool-dependencies tool-observations)
      (module-compiler-tools))
    (def (current!)
      (parameterize ((current-module-source-phase 'configuration-current))
        (call-with-module-source-read-cache
          (lambda ()
            (module-source-admit-current! (hash->list tool-observations) "compiler tool source changed")
            (for-each (lambda (input) ((.ref input 'admit-current))) inputs)))))
    (def (write-input! input)
      (let* ((path (.ref input 'path))
             (owner (path-directory (path-normalize (.ref prepared 'path))))
             (shared (and shared-contexts
                          (not (string-prefix? owner (path-normalize path)))
                          (hash-get shared-contexts (path-normalize path)))))
        ;; The existing publication reader already owns this exact dependency
        ;; context and its input. Do not expand/initialize its source again.
        ;; Owner roles remain private fresh wrappers, including changed configs.
        (if shared
          (hash-put! wrappers (path-normalize path) (cons input shared))
          (let (wrapper (path-expand (string-append (symbol->string (gensym 'role-)) ".ss") directory))
            (hash-put! wrappers (path-normalize path) wrapper)
            (hash-put! owned (path-normalize wrapper) #t)
            (call-with-output-file wrapper
              (lambda (port)
                (write 'package: port) (display " " port) (write prefix port) (newline port)
                (for-each (lambda (form) (write form port) (newline port))
                  (append (if (and role-imports? (eq? input prepared))
                            (list `(import :clan/poo/object
                                           ,@(map (cut .ref <> 'path) related))) '())
                          (reader-body (.ref input 'compiler-forms))
                          (if (eq? input prepared) (list `(export ,binding)) '())))))))))
    ;; Private dependencies are the exact source closure already observed by
    ;; publication reading. Owner-private inputs receive wrappers; recorded
    ;; dependency contexts retain their identities. Neither is injected as roles.
    ;; Config evaluation keeps its explicit admitted-role-only boundary.
    (current!)
    (dynamic-wind
     (lambda ()
       (create-directory* directory)
       (for-each write-input! inputs))
     (lambda ()
       (let (result
             (parameterize
                 ((current-expander-context (make-top-context))
                  (current-expander-compile compile)
                  (current-expander-eval evaluate)
                  (current-expander-module-import
                   (lambda (path (reload? #f))
                     (let (target (and (string? path) (hash-get wrappers (path-normalize path))))
                       (cond
                         ((pair? target)
                          (when reload? (error "shared publication context reload requires a fresh reader"))
                          ((.ref (car target) 'admit-current))
                          (cdr target))
                         (target (native-import target reload?))
                         ;; Keep this interceptor active while expanding our own
                         ;; generated entry. Otherwise its relative role imports
                         ;; escape to the native original-path registry, and a
                         ;; fresh source epoch can silently reuse an old value.
                         ((and (string? path) (string-prefix? directory path))
                          (native-import path reload?))
                         ((and (string? path) (hash-get tool-paths (path-normalize path)))
                          => (lambda (context)
                               (when reload? (error "compiler tool reload requires a fresh configuration context"))
                               (unless (eq? context (hash-get tool-contexts (expander-context-id context)))
                                 (error "compiler tool context changed during configuration"))
                               (parameterize ((current-module-source-phase 'configuration-import))
                                 (admit-compiler-inputs! context tool-dependencies))
                               context))
                         ((and shared-contexts shared-inputs (string? path)
                               (not (string-prefix?
                                      (path-directory (path-normalize (.ref prepared 'path)))
                                      (path-normalize path)))
                               (hash-get shared-contexts (path-normalize path)))
                          => (lambda (context)
                               (when reload? (error "shared publication context reload requires a fresh reader"))
                               (let (input (hash-get shared-inputs context))
                                 (unless input (error "shared publication context has no guarded source" path))
                                 ;; Build-only imports may use another selected
                                 ;; module's existing dependency context. Enroll
                                 ;; its exact observed closure, never scan a dir.
                                 (for-each-build-module context
                                   (lambda (child)
                                     (let (source (hash-get shared-inputs child))
                                       (when (and source (not (memq source inputs)))
                                         (set! inputs (cons source inputs))))))
                                 ((.ref input 'admit-current))
                                 (hash-put! wrappers (path-normalize path) (cons input context))
                                 context)))
                         ((and (string? path) (string=? (path-extension path) ".ss")
                               (not (string-prefix? directory path)))
                          (let (input (public-dependency-input path))
                            (unless input
                              (error "configuration import requires an admitted role or prebuilt library" path))
                            (when reload? (error "public dependency reload requires a fresh environment"))
                            (set! inputs (cons input inputs))
                            ((.ref input 'admit-current))
                            (parameterize ((current-expander-module-import native-import))
                              (native-import path #f))))
                         (else (parameterize ((current-expander-module-import native-import))
                                 (native-import path reload?))))))))
               (eval-syntax `(import ,(hash-ref wrappers (path-normalize (.ref prepared 'path)))))
               (eval-syntax binding)))
         (current!)
         (release-reader-expansions! completed)
         result))
     (lambda () (remove-reader-tree directory)))))
