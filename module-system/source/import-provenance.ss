;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Record the origin of Gerbil import contexts and authenticate their source support.
;;; Gerbil owns module resolution and loading. std/make owns compilation.
(import (only-in :gerbil/expander core-resolve-library-module-path core-library-package-path-prefix
                 expander-context-id module-context-path module-context? __module-registry)
        (only-in :clan/poo/object .ref)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :clan/poo/slot-observation without-observation)
        (only-in :clan/poo/read-projection owned-read-function-scope?)
        :tao3k/yuanxu/module-system/source/reader-support
        :tao3k/yuanxu/module-system/source/preparation
        :tao3k/yuanxu/module-system/source/admission
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module
                 yuanxu-reader-contexts call-with-build-stage)
        (only-in :tao3k/yuanxu/module-system/building/source-package module-build-source-path))
(export public-dependency-input admit-compiler-inputs!
        compiler-tool-inputs compiler-tool-input record-source-observations!
        compiler-context-origin-current? captured-import-context? module-import-provenance)

;; One canonical-library check for publication and configuration readers. This
;; prepares observations, never imports, expands or initializes the dependency.
(def (public-dependency-input path (prepared #f) (report-refusal? #f)
                              capture: (capture #f) binding: (binding #f) bind: (bind void)
                              owned-root: (owned-root #f))
  ;; Eligibility probes may return #f. A previously enrolled dependency must
  ;; retain its actual refusal cause; do not replace a stale-source error with
  ;; an ambiguous runtime-identity message. No check is repeated for reporting.
  (def (refuse . detail)
    (when report-refusal?
      (apply error "public dependency source or runtime identity changed" path detail))
    #f)
  (let* ((input (with-catch (lambda (cause) (refuse 'source-preparation cause))
                  (lambda ()
                    (if prepared
                      (begin ((.ref prepared 'admit-current)) prepared)
                      (yuanxu-prepare-module-tool-source path void capture: capture)))))
         (identity (and input (.ref input 'compiler-identity)))
         (selected (and input (module-compiler-source-input path)))
         ;; Gerbil resolves the actual public binding. Namespace spelling is
         ;; neither source ownership nor permission to reuse a compiler context.
         (external? (symbol? identity))
         (selected? (and external? selected (eq? identity (.ref selected 'compiler-identity))))
         (resolved
          (if selected? path
            (and external?
              (with-catch (lambda (cause) (refuse 'runtime-resolution cause))
                (lambda ()
                  (core-resolve-library-module-path
                    (string->symbol (string-append ":" (symbol->string identity))))))))))
    ;; A native SSI may legitimately coexist with its owned source. Bind only
    ;; an ALREADY imported actual context, never permission inferred from an
    ;; artifact suffix or a matching filename. Keep that instance/name/path for
    ;; later checks; changing load-path cannot retarget this observation.
    (def compiled
      (and (string? resolved) (string=? (path-extension resolved) ".ssi")
        (let (context (or (hash-get __module-registry resolved)
                         (hash-get __module-registry (path-normalize resolved))))
          (and (module-context? context) (eq? identity (expander-context-id context))
               (string? (module-context-path context))
               (equal? (path-normalize resolved) (path-normalize (module-context-path context)))
               (vector context identity (string-copy (module-context-path context)))))))
    (def observed
      (or (and binding (vector-ref binding 0) binding)
          (and owned-root compiled)
          binding
          (and (string? resolved) (equal? (path-normalize resolved) (path-normalize path))
               (vector #f identity (string-copy path)))
          compiled))
    (def binding-current?
      (or (not observed)
          (and (eq? identity (vector-ref observed 1))
               (or (not (vector-ref observed 0))
                   (begin
                     (require-read-route! 'compiler-module-cache __module-registry #f)
                     (and (eq? identity (expander-context-id (vector-ref observed 0)))
                          (equal? (vector-ref observed 2) (module-context-path (vector-ref observed 0)))
                          (eq? (vector-ref observed 0)
                               (or (hash-get __module-registry (vector-ref observed 2))
                                   (hash-get __module-registry (path-normalize (vector-ref observed 2)))))))))))
    (if (and binding-current? (string? resolved)
             (or selected?
                 (and (equal? (path-normalize resolved) (path-normalize path))
                      (or owned-root
                          (equal? (path-normalize path)
                                  (path-normalize (if observed (vector-ref observed 2) path)))))
                 ;; Same-package source may already have a compiled Gerbil context.
                 ;; Retain that exact binding and validate the declared source owner.
                 (and owned-root observed (vector-ref observed 0)
                      (equal? (path-normalize resolved)
                              (path-normalize (vector-ref observed 2)))
                      (let (source (module-build-source-path (vector-ref observed 0) owned-root))
                        (and source (equal? (path-normalize source) (path-normalize path)))))))
      (begin (bind observed) input)
      (refuse 'expected-identity identity 'resolved-path resolved))))
;; Check the demanded Gerbil dependency subgraph, not every selected role on each
;; import edge. Complete role/asset guards still bracket expansion/evaluation.
(def (admit-compiler-inputs! context inputs-for (visit (lambda (_input) (void))))
  (module-source-measure-operation 'reader-tool-inputs
   (lambda () (call-with-module-source-read-cache
    (lambda ()
      (for-each
        (lambda (input)
          (module-source-admit-current! (.ref input 'source-inputs))
          (visit input))
        (inputs-for context)))))))
;; Preparation is determined by an actual Gerbil expander context and its observed source.
;; Keep the projection, never an admission result. Every reuse checks bytes and
;; runtime package identity again; changed code needs a fresh compiler context.
(def compiler-tool-inputs (make-hash-table-eq weak-keys: #t))
(def (compiler-tool-input context path (owner-projection? #f))
  (let* ((normalized (path-normalize path))
         (previous (hash-get compiler-tool-inputs context)))
    (if previous
      (begin
        (unless (equal? normalized (source-preparation-path previous))
          (error "compiler tool source path changed" path))
        ;; Owner projection only builds a private list. Its consumer checks
        ;; this exact input again after enrollment, before exposing the native
        ;; context. Keep that later guard and elide the earlier duplicate only
        ;; for an authenticated native source checker in a closed read scope.
        (if (and owner-projection? (not (current-module-source-observer))
                 (owned-read-function-scope?)
                 (without-observation (lambda () (source-preparation-current? previous))))
          (module-source-measure-operation 'compiler-tool-input-deferred void)
          (module-source-measure-operation 'compiler-tool-input-current
            (.ref (source-preparation-value previous) 'admit-current)))
        (source-preparation-value previous))
      (let* ((origin #f)
             (input (yuanxu-prepare-module-tool-source path void
                      capture: (lambda (value checker path ready? state)
                                 (set! origin (capture-source-preparation value checker path ready? state)) value))))
        (unless (eq? (expander-context-id context) (.ref input 'compiler-identity))
          (error "compiler tool source identity mismatch" (expander-context-id context) path))
        (hash-put! compiler-tool-inputs context origin)
        input))))
(def (record-source-observations! observations rows)
  (for-each
    (lambda (observation)
      (let (file (car observation))
        (when (and (hash-key? observations file)
                   (not (equal? (hash-ref observations file) (cdr observation))))
          (error "inconsistent compiler tool source observations" file))
        (hash-put! observations file (cdr observation)))) rows))
(def (compiler-context-origin-current? context origin)
  (and origin (eq? (car origin) (expander-context-id context))
       (equal? (cdr origin) (module-context-path context))))
(def (captured-import-context? contexts context)
  ;; Point queries authenticate the actual captured instance before reading it.
  (compiler-context-origin-current? context (hash-get contexts context)))
(def (module-import-provenance)
  (def compiler-contexts (make-hash-table-eq))
  (def tool-contexts
    (yuanxu-reader-contexts
      (lambda (context)
        (let (path (module-context-path context))
          (hash-put! compiler-contexts context
            (cons (expander-context-id context) (if (string? path) (string-copy path) path)))))))
  (def tool-paths (make-hash-table))
  (def tool-path-candidates (make-hash-table))
  (def (index-tool-path! path context)
    (hash-update! tool-path-candidates (path-normalize path) (cut cons context <>) '()))
  (def tool-inputs (make-hash-table-eq))
  (def tool-observations (make-hash-table))
  (def dependency-index (make-hash-table-eq))
  (def (record-tool-input! input)
    ;; Keep observations of actual import demands, not the capability catalog.
    ;; These are immutable expected bytes; every guard still reads current bytes.
    (record-source-observations! tool-observations (.ref input 'source-inputs)))
  (def (inputs-for context (source-root #f))
    ;; Cache only the immutable Gerbil import graph for this reader snapshot.
    ;; Every caller above still checks the actual source observations; no
    ;; acceptance or initializer result is stored in this structural index.
    (when (current-module-source-observer)
      ((current-module-source-observer) 'compiler-closure-requests 1)
      ((current-module-source-observer) (list 'compiler-demand context) 1))
    (def contexts
     (if (hash-key? dependency-index context)
      (hash-ref dependency-index context)
      (let (contexts '())
        (when (current-module-source-observer)
          ((current-module-source-observer) 'compiler-closure-walks 1))
        (for-each-build-module context
          (lambda (child)
            (set! contexts (cons child contexts))
            (when (current-module-source-observer)
              ((current-module-source-observer)
                (list 'compiler-discovery context child (module-context-path child)) 1)
              ((current-module-source-observer) 'compiler-enrollment 1))
            (let (input (hash-get tool-inputs child))
              (when input
                (record-tool-input! input)))))
        (let (ordered (reverse contexts))
          ;; Enrollment is structural, unlike source admission. The SAME
          ;; immutable closure is already enrolled on an index hit; walking
          ;; it again only adds duplicate POO reads to the caller's recording.
          ;; Do this before exposing the index entry. Every import still runs
          ;; admit-compiler-inputs! over the demanded closure with fresh bytes.
          (hash-put! dependency-index context ordered)
          ordered))))
    (if source-root
      ;; Build source is a separate owner demand. Installed execution does not
      ;; acquire authority over its checkout by projecting an SSI back to SS.
      (let ((prefix (core-library-package-path-prefix source-root))
            (root-prefix (string-append
                           (path-strip-trailing-directory-separator (path-normalize source-root)) "/")))
        (filter-map
          (lambda (child)
            (let (id (expander-context-id child))
              (and prefix (symbol? id) (string-prefix? prefix (symbol->string id))
                   (let* ((origin (hash-get compiler-tool-inputs child))
                          (bound (and origin (source-preparation-path origin)))
                          ;; The SAME native preparation already binds this
                          ;; context to its owner path. Re-resolving/parsing the
                          ;; entire file adds no identity evidence. Still invoke
                          ;; its original byte/package checker on EVERY demand;
                          ;; removal must refuse, never drop the owned input.
                          (path (if (and bound (string-prefix? root-prefix bound))
                                  (begin
                                    (module-source-measure-operation 'reader-bound-source-reuse void)
                                    bound)
                                  (module-source-measure-operation 'reader-owned-source-resolution
                                    (lambda () (module-build-source-path child source-root))))))
                     (and path (compiler-tool-input child path #t)))))) contexts))
      (filter-map (cut hash-get tool-inputs <>) contexts)))
  ;; Reuse only exact Gerbil-observed compiler contexts. A source path or Core-like
  ;; identity alone grants no exemption from publication source confinement.
  (def (capture-tool-sources!)
   (parameterize ((current-module-source-phase 'import-provenance))
   (call-with-module-source-read-cache
    (lambda ()
      (for-each
        (lambda (context)
          (let* ((id (expander-context-id context))
                 (artifact-path (module-context-path context))
                 (source? (and (string? artifact-path) (string=? (path-extension artifact-path) ".ss")))
                 ;; Observe Gerbil's actual source context. Source aliases for
                 ;; compiled contexts require the caller's declared source-root
                 ;; in inputs-for; never reconstruct a vanished compiler tree.
                 (path (and source? artifact-path)))
            ;; The captured runtime Gerbil closure also contains gerbil-poo and
            ;; other source libraries. Guard those actual inputs in the SAME
            ;; dependency index, rather than importing them again as unknown
            ;; public initializers for every Module. Compiled Gerbil expander contexts keep
            ;; their existing package/runtime trust boundary.
            (when (and (symbol? id) (string? artifact-path)
                       (string=? (path-extension artifact-path) ".ssi"))
              (index-tool-path! artifact-path context))
            (when (and (symbol? id)
                       (string? path) (string=? (path-extension path) ".ss"))
              (index-tool-path! path context)
              (let (input (compiler-tool-input context path))
                (unless (eq? id (.ref input 'compiler-identity))
                  (error "compiler tool source identity mismatch" id path))
                (hash-put! tool-inputs context input)))))
        (hash-keys compiler-contexts))))))
  (call-with-build-stage 'compiler-tool-sources capture-tool-sources!)
  ;; Exact runtime origin wins over a compiled context's source projection.
  ;; Competing instances at the same origin remain an error, never hash-order
  ;; selection or permission inferred from a shared module identity.
  (hash-for-each
    (lambda (path contexts)
      (def exact
        (filter (lambda (context)
                  (let (runtime (module-context-path context))
                    (and (string? runtime) (equal? path (path-normalize runtime))))) contexts))
      (def choices (if (pair? exact) exact contexts))
      (unless (and (pair? choices) (null? (cdr choices)))
        (error "compiler tool path has competing runtime contexts" path))
      (hash-put! tool-paths path (car choices)))
    tool-path-candidates)
  ;; The interpreter itself is always used, independently of author imports.
  ;; Preserve its exact runtime closure; later imports monotonically add demands.
  ;; The catalog grants import eligibility, never evidence of actual use.
  (inputs-for (hash-ref tool-contexts 'tao3k/yuanxu/module-system/source/reader))
  (values tool-contexts tool-paths inputs-for tool-observations compiler-contexts))
