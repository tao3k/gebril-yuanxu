;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; This owner deliberately imports only the Gerbil. It can discover the Core
;;; build-tool closure before any application Module has been compiled.
(import (only-in :gerbil/expander core-import-module current-expander-context make-top-context
                 current-expander-module-import expander-context-id
                 module-context? module-context-import module-context-path module-context-export
                 core-context-prelude prelude-context? prelude-context-import
                 prelude-context-path __module-registry
                 core-library-package-path-prefix core-library-package-plist
                 module-import? module-import-source module-export? module-export-context
                 import-set? import-set-source)
        (only-in :std/source this-source-file)
        (only-in "./source-package.ss" module-build-source-path))
(export yuanxu-bootstrap-spec for-each-build-module build-module-dependencies yuanxu-bootstrap-contexts
        yuanxu-library-identity? package-library-spec package-library-spec/source-context
        call-with-build-expansion-accounting
        call-with-build-stage)

(def (call-with-build-stage stage action)
  (def verbosity (string->number (getenv "GERBIL_BUILD_VERBOSE" "0")))
  (if (and verbosity (>= verbosity 2))
    (begin
      (displayln "BUILD-STAGE " stage " enter at=" (real-time)) (force-output)
      (begin0 (action)
        (displayln "BUILD-STAGE " stage " return at=" (real-time)) (force-output)))
    (action)))

;; Diagnostic census of Gerbil's real registered contexts, not import request
;; counts. No source is imported, evaluated or approved by this observation.
;; Enable with the existing build verbosity; ordinary builds pay no census cost.
(def (call-with-build-expansion-accounting stage action)
  (def verbosity (string->number (getenv "GERBIL_BUILD_VERBOSE" "0")))
  (if (not (and verbosity (>= verbosity 2))) (action)
    (let ((before (make-hash-table-eq)) (created (make-hash-table-eq)))
      (hash-for-each (lambda (_key value)
                       (when (module-context? value)
                         (hash-put! before value #t)
                         ;; Symbols and native context objects are disjoint
                         ;; keys. This phase-local census is diagnostic ONLY;
                         ;; never resolve or authorize an import from it.
                         (let (identity (expander-context-id value))
                           (when (symbol? identity) (hash-put! before identity value))))) __module-registry)
      (when (eq? stage 'std-make)
        (displayln "BUILD-STAGE std-make enter at=" (real-time))
        (force-output))
      (begin0 (action)
        (hash-for-each
          (lambda (_key value)
            (when (and (module-context? value) (not (hash-key? before value)))
              (hash-put! created value #t))) __module-registry)
        (write (list 'BUILD-EXPANSION stage (hash-length created))) (newline)
        (let ((mirrors 0) (samples 0))
          (hash-for-each
            (lambda (context _present)
              (let* ((identity (expander-context-id context))
                     (previous (hash-get before identity)))
                (when (module-context? previous) (set! mirrors (+ mirrors 1)))
                (when (< samples 6)
                  (set! samples (+ samples 1))
                  (write (list 'BUILD-CONTEXT-SAMPLE stage identity (module-context-path context)
                               (and (module-context? previous) (module-context-path previous))))
                  (newline)))) created)
          (write (list 'BUILD-CONTEXT-MIRRORS stage mirrors)) (newline))
        (force-output)))))

;; Project an explicitly selected package's actual runtime import graph. This
;; function does not discover roots, load their runtime, or execute a build.
;; std/make retains dependency/currentness/compilation ownership.
(def (package-library-spec root package entries
                          admit-context: (admit-context void)
                          exclude: (excluded '()))
  (library-spec root package entries admit-context excluded identity))

(def (package-library-spec/source-context root package entries admit-context source-context)
  (library-spec root package entries admit-context '() source-context))

(def (library-spec root package entries admit-context excluded source-context)
  (def prefix (string-append (symbol->string package) "/"))
  (def seen (make-hash-table-eq))
  (def paths (make-hash-table))
  (def targets '())
  (def verbosity (string->number (getenv "GERBIL_BUILD_VERBOSE" "0")))
  (def started (and verbosity (>= verbosity 2) (real-time)))
  (when started
    (displayln "BUILD-STAGE library-spec enter at=" started) (force-output))
  (def (visit context)
    (admit-context context)
    (let* ((identity (expander-context-id context))
           (name (and (symbol? identity) (symbol->string identity))))
      (when (and name (string-prefix? prefix name))
        (let (relative (substring name (string-length prefix) (string-length name)))
          (unless (or (member relative excluded) (hash-key? paths relative))
            (hash-put! paths relative #t)
            (set! targets (cons relative targets)))))))
  (call-with-build-expansion-accounting 'library-spec
    (lambda ()
      (for-each
        (lambda (file)
          (walk-build-modules (core-import-module (path-expand file root)) visit seen
            (lambda (_) #t) source-context))
        entries)))
  (when started
    (displayln "BUILD-STAGE library-spec return at=" (real-time)
               " seconds=" (- (real-time) started) " targets=" (length targets))
    (force-output))
  (reverse targets))

(def (for-each-build-module root visit
                           (seen (make-hash-table-eq))
                           (descend? (lambda (_context) #t)))
  (walk-build-modules root visit seen descend? identity))

(def (build-module-context value)
    (cond
     ((module-import? value) (build-module-context (module-import-source value)))
     ((module-export? value) (build-module-context (module-export-context value)))
     ((import-set? value) (build-module-context (import-set-source value)))
     (else value)))
(def (build-module-dependencies context)
    (let* ((prelude (core-context-prelude context))
           (imports (module-context-import context)))
      (if (and (prelude-context? prelude) (expander-context-id prelude))
        (cons prelude imports) imports)))

(def (walk-build-modules root visit seen descend? source-context)
  ;; A caller walking several already imported roots may share this traversal's
  ;; visited set. It never survives an independent closure request.
  ;; Hoist the live frame into tail-call arguments. Repeated aliases previously
  ;; allocated a new frame/spine even when their owner was already seen. Suspend
  ;; only when descending into a NEW context; no runtime metadata is mutated.
  ;; Postorder, shared seen identity, callbacks and continuation behavior remain
  ;; unchanged. No topology or successful check survives this invocation.
  (let walk ((pending (list root)) (after #f) (frames '()))
    (if (null? pending)
      (begin
        (when after (visit after))
        (when (pair? frames)
          (walk (caar frames) (cdar frames) (cdr frames))))
      (let* ((context (build-module-context (car pending)))
             (value (if (module-context? context) (source-context context) context)))
        (cond
         ((and (prelude-context? value) (not (hash-key? seen value)))
          (hash-put! seen value #t)
          (walk (cons (runtime-prelude-owner value) (cdr pending)) after frames))
         ((and (module-context? value) (not (hash-key? seen value)))
          (begin
            (hash-put! seen value #t)
            (if (descend? value)
              (walk (build-module-dependencies value) value (cons (cons (cdr pending) after) frames))
              (begin (visit value) (walk (cdr pending) after frames)))))
         (else (walk (cdr pending) after frames)))))))

(def (runtime-prelude-owner prelude)
  ;; Gerbil also constructs preludes directly, without registering the reverse
  ;; association made by core-module->prelude-context. Its constructor retains
  ;; the exact ordered module exports in the import payload. Check that complete
  ;; association rather than guessing an owner from one exported binding.
  ;; Neither path imports a module, initializes a language or adds a registry.
  ;; Path/ID hits are only candidates: source and compiled contexts can share
  ;; an ID, and reload can replace the path entry while the old context lives.
  (def (owns? context)
    (and (module-context? context)
         (eq? (hash-get __module-registry context) prelude)))
  (def (payload-owner)
    (let (imports (prelude-context-import prelude))
      (and (pair? imports) (andmap module-import? imports)
           (let (exports (map module-import-source imports))
             (and (andmap module-export? exports)
                  (let (context (module-export-context (car exports)))
                    (and (module-context? context)
                         (eq? (expander-context-id context) (expander-context-id prelude))
                         (equal? (module-context-path context) (prelude-context-path prelude))
                         (let (declared (module-context-export context))
                           (and (= (length exports) (length declared))
                                (andmap (lambda (entry expected)
                                          (and (eq? entry expected)
                                               (eq? (module-export-context entry) context)))
                                        exports declared)))
                         context)))))))
  (let ((by-path (hash-get __module-registry (prelude-context-path prelude)))
        (by-id (hash-get __module-registry (expander-context-id prelude))))
    (cond ((owns? by-path) by-path)
          ((owns? by-id) by-id)
          (else
           (or (payload-owner)
               (let/cc found
                 (hash-for-each
                   (lambda (context registered)
                     (when (and (eq? registered prelude) (module-context? context))
                       (found context))) __module-registry)
                 (error "prelude has no runtime module association" (expander-context-id prelude))))))))
;; Closed Core tools: build projection and ordinary data construction. Published
;; Modules remain selected dependencies, never implicit bootstrap capabilities.
(def bootstrap-roots '(:yuanxu/module-system/building/build-projection
                      ;; The reader emits these two fixed role languages. They
                      ;; are compiler dependencies, not selected business roles.
                      ;; Empty only-in imports do not survive Gerbil's compiled
                      ;; import graph, so root their actual native contexts here.
                      :yuanxu/module-system/source/module-prelude
                      :yuanxu/module-system/source/config-prelude
                      ;; The Gerbil consumer is part of the compiler trust closure.
                      :yuanxu/module-system/building/script
                      :yuanxu/module-system/building/configuration-source
                      ;; Shared graph values/algorithms are kernel data APIs.
                      ;; Selected Ops/Funflow sources use this same closure;
                      ;; no Module scope or runtime activation is granted here.
                      :yuanxu/graph/types-core
                      :yuanxu/graph/algorithms
                      ;; Task/Flow Contracts are shared functional kernel
                      ;; definitions. Module descriptors must use their actual
                      ;; runtime instances, not private re-evaluated copies.
                      ;; This library imports no runner or Module scope. Only
                      ;; actual imports enroll its source support in the reader.
                      :yuanxu/modules/funflow/control-plane/flow
                      ;; The workflow value crosses the same library/Module
                      ;; boundary; its Record family must not be cloned.
                      :yuanxu/modules/funflow/scenario
                      ;; Bounded declaration syntax constructs ordinary POO
                      ;; defaults; it does not import selection or activation.
                      :yuanxu/profile-composition/module-prototype-syntax
                      ;; Public artifact/IR identity is shared with Core admission.
                      ;; These are library definitions, not a linked Module scope.
                      :yuanxu/modules/json-schema/json-schema-receipt
                      ;; Validation results and diagnostics cross the same public
                      ;; boundary; their runtime record identities must also agree.
                      :yuanxu/modules/json-schema/json-schema-validate
                      ;; Source-bound contracts are ordinary Core definitions
                      ;; used by relocated publications, not a Module scope.
                      :yuanxu/admission/source
                      :yuanxu/configuration/diagnostics
                      ;; Shared field Types belong to the same authenticated
                      ;; library closure as Contracts, including relocated roles.
                      :yuanxu/object-types/ports))
;; Flow imports role-syntax. The reader and diagnostics import configuration/json.
;; Their native dependency edges supply both Contexts to the same catalog walk.
(def (yuanxu-bootstrap-contexts (observe-context void))
  ;; Finish runtime imports before sharing DFS state. No observation window or
  ;; successful source check crosses a macro/initializer boundary here.
  (def verbosity (string->number (getenv "GERBIL_BUILD_VERBOSE" "0")))
  (def trace? (and verbosity (>= verbosity 2)))
  (def (import-root name)
    (let ((registered (and trace? (hash-get __module-registry name)))
          (started (and trace? (real-time))))
      (let (context (core-import-module name))
        (when trace?
          (write (list 'BUILD-BOOTSTRAP-ROOT name
                       (if (eq? context registered) 'registered 'resolved)
                       (- (real-time) started)
                       (expander-context-id context) (module-context-path context)))
          (newline) (force-output))
        context)))
  (def roots
    (call-with-build-stage 'compiler-tool-imports
      (lambda () (map import-root bootstrap-roots))))
  (def ids (make-hash-table))
  (def seen (make-hash-table-eq))
  (call-with-build-stage 'compiler-tool-catalog
    (lambda ()
      (for-each
        (lambda (name root)
          (when trace?
            (write (list 'BUILD-BOOTSTRAP-COVERAGE name (hash-key? seen root)))
            (newline))
          (for-each-build-module root
            (lambda (context)
              ;; Retain each actual context even when source and compiled
              ;; interfaces declare the same identity.
              (observe-context context)
              (hash-put! ids (expander-context-id context) context))
            seen))
        bootstrap-roots roots)))
  ids)
(def library-source-root (path-normalize (path-expand "../.." (path-directory (this-source-file)))))
(def (configured-language-identity root)
  (let* ((language (pgetq prelude: (core-library-package-plist root)))
         (name (and (symbol? language) (symbol->string language))))
    (and name (string-prefix? ":" name)
         (string->symbol (substring name 1 (string-length name))))))
(def (yuanxu-library-identity? identity)
  (and (symbol? identity)
       (or (let (prefix (core-library-package-path-prefix library-source-root))
             (and prefix (string-prefix? prefix (symbol->string identity))))
           (eq? identity (configured-language-identity library-source-root)))))
(def (yuanxu-bootstrap-spec core-root)
  (using (core-root :~ string?)
    (let* ((root (string-append (path-strip-trailing-directory-separator (path-normalize core-root)) "/")) (seen (make-hash-table)) (rows '())
           (gerbil-import (current-expander-module-import)))
      (def (source-for context)
        (module-build-source-path context root))
      (def (visit context)
        (let (source (source-for context))
          (when (and source (not (hash-key? seen source)))
            (hash-put! seen source #t)
            (set! rows (cons `(gxc: ,(path-strip-extension (substring source (string-length root) (string-length source)))) rows)))))
      (parameterize
          ((current-expander-context (make-top-context))
           (current-expander-module-import
            (lambda (path (reload? #f))
              (let* ((context (gerbil-import path reload?)) (source (source-for context)))
                (if (and source (not (equal? (path-normalize source) (path-normalize (module-context-path context)))))
                  (gerbil-import source reload?) context)))))
        (for-each
          (lambda (identity)
            (let (source (source-for (gerbil-import identity)))
              (unless source (error "compiler source unavailable" identity root))
              (for-each-build-module
                (core-import-module source) visit)))
          bootstrap-roots))
      (reverse rows))))
