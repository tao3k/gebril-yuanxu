;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; This owner deliberately imports only the SDK. It can discover the Core
;;; build-tool closure before any application Module has been compiled.
(import (only-in :gerbil/expander core-import-module current-expander-context make-top-context
                 current-expander-module-import expander-context-id
                 module-context? module-context-import module-context-path
                 core-context-prelude prelude-context? prelude-context-import
                 module-import? module-import-source module-export? module-export-context
                 import-set? import-set-source))
(export yuanxu-bootstrap-spec for-each-build-module yuanxu-bootstrap-contexts
        yuanxu-bootstrap-source-path yuanxu-library-identity? package-library-spec)

;; Project an explicitly selected package's actual native import graph. This
;; function does not discover roots, load their runtime, or execute a build.
;; std/make retains dependency/currentness/compilation ownership.
(def (package-library-spec root package entries
                          admit-context: (admit-context void)
                          exclude: (excluded '()))
  (def prefix (string-append (symbol->string package) "/"))
  (def seen (make-hash-table-eq))
  (def paths (make-hash-table))
  (def targets '())
  (def (visit context)
    (admit-context context)
    (let* ((identity (expander-context-id context))
           (name (and (symbol? identity) (symbol->string identity))))
      (when (and name (string-prefix? prefix name))
        (let (relative (substring name (string-length prefix) (string-length name)))
          (unless (or (member relative excluded) (hash-key? paths relative))
            (hash-put! paths relative #t)
            (set! targets (cons relative targets)))))))
  (for-each
    (lambda (file)
      (for-each-build-module (core-import-module (path-expand file root)) visit seen))
    entries)
  (reverse targets))

(def (for-each-build-module root visit
                           (seen (make-hash-table-eq))
                           (descend? (lambda (_context) #t)))
  ;; A caller walking several already imported roots may share this traversal's
  ;; visited set. It never survives an independent closure request.
  (def (context-of value)
    (cond
     ((module-import? value) (context-of (module-import-source value)))
     ((module-export? value) (context-of (module-export-context value)))
     ((import-set? value) (context-of (import-set-source value)))
     (else value)))
  (def (dependencies context)
    ;; Native prelude exports point back to their module owner. Project that
    ;; owner once, rather than walking thousands of aliases to the SAME module.
    ;; Its e field is a delayed evaluator and is never forced for discovery.
    (let* ((prelude (core-context-prelude context))
           (entries (and (prelude-context? prelude) (prelude-context-import prelude)))
           (imports (module-context-import context)))
      (if (and entries (pair? entries))
        (let (owner (context-of (car entries)))
          (unless (and (module-context? owner)
                       (eq? (expander-context-id owner) (expander-context-id prelude)))
            (error "selected prelude export owner mismatch" (expander-context-id context)))
          (cons owner imports))
        (begin
          (when (and (prelude-context? prelude) (expander-context-id prelude))
            (error "selected prelude has no observable export owner" (expander-context-id context)))
          imports))))
  ;; Each frame owns remaining siblings and the context to visit AFTER them.
  ;; Preserve the original postorder, shared seen identity and callback timing.
  ;; Host continuation depth no longer follows native import depth. No context
  ;; topology or successful source check survives this traversal invocation.
  (let walk ((frames (list (cons (list root) #f))))
    (when (pair? frames)
      (let* ((frame (car frames)) (pending (car frame)) (after (cdr frame)))
        (if (null? pending)
          (begin (when after (visit after)) (walk (cdr frames)))
          (let* ((value (context-of (car pending)))
                 (remaining (cons (cons (cdr pending) after) (cdr frames))))
            (if (and (module-context? value) (not (hash-key? seen value)))
              (begin
                (hash-put! seen value #t)
                (if (descend? value)
                  (walk (cons (cons (dependencies value) value) remaining))
                  (begin (visit value) (walk remaining))))
              (walk remaining))))))))
;; Closed Core tools: build projection and ordinary data construction. Published
;; Modules remain selected dependencies, never implicit bootstrap capabilities.
(def bootstrap-roots '(:yuanxu/module-system/building/build-projection
                      ;; The SDK consumer is part of the compiler trust closure.
                      :yuanxu/module-system/building/script
                      :yuanxu/module-system/building/configuration-source
                      ;; Shared graph values/algorithms are kernel data APIs.
                      ;; Selected Ops/Funflow sources use this same closure;
                      ;; no Module scope or runtime activation is granted here.
                      :yuanxu/graph/types-core
                      :yuanxu/graph/algorithms
                      ;; Bounded declaration syntax constructs ordinary POO
                      ;; defaults; it does not import selection or activation.
                      :yuanxu/profile-composition/module-prototype-syntax
                      ;; Public artifact/IR identity is shared with Core admission.
                      ;; These are library definitions, not a linked Module scope.
                      :yuanxu/modules/json-schema/json-schema-receipt
                      ;; Validation results and diagnostics cross the same public
                      ;; boundary; their native record identities must also agree.
                      :yuanxu/modules/json-schema/json-schema-validate
                      ;; Source-bound contracts are ordinary Core definitions
                      ;; used by relocated publications, not a Module scope.
                      :yuanxu/admission/source
                      ;; Export binding consumes this platform-owned protocol;
                      ;; importing it neither selects a scope nor publishes one.
                      :yuanxu/admission/publication
                      :yuanxu/configuration/diagnostics
                      ;; Shared field Types belong to the same authenticated
                      ;; library closure as Contracts, including relocated roles.
                      :yuanxu/object-types/ports
                      :yuanxu/object-family/role-syntax
                      :yuanxu/configuration/json))
(def (yuanxu-bootstrap-contexts)
  ;; Finish native imports before sharing DFS state. No observation window or
  ;; successful source check crosses a macro/initializer boundary here.
  (let ((roots (map core-import-module bootstrap-roots))
        (ids (make-hash-table)) (seen (make-hash-table-eq)))
    (for-each (lambda (root)
                (for-each-build-module root
                  (lambda (context) (hash-put! ids (expander-context-id context) context))
                  seen))
              roots)
    ids))
(def (library-relative-source identity)
  (and (symbol? identity)
    (if (eq? identity 'tao3k/yuanxu/prelude) "prelude.ss"
      (let (text (symbol->string identity))
        (and (string-prefix? "yuanxu/" text)
          (string-append (substring text (string-length "yuanxu/") (string-length text)) ".ss"))))))
(def (yuanxu-library-identity? identity)
  (and (library-relative-source identity) #t))
(def (yuanxu-bootstrap-source-path context core-root)
  ;; A caller supplies an already SDK-observed context and the trusted Core
  ;; source root. This is the same source projection used by bootstrap itself.
  (let (relative (library-relative-source (expander-context-id context)))
    (and relative (let (source (path-expand relative core-root))
                    (and (file-exists? source) source)))))
(def (yuanxu-bootstrap-spec core-root)
  (using (core-root :~ string?)
    (let* ((root (string-append (path-strip-trailing-directory-separator (path-expand core-root)) "/")) (seen (make-hash-table)) (rows '())
           (native-import (current-expander-module-import)))
      (def (source-for context)
        (yuanxu-bootstrap-source-path context root))
      (def (visit context)
        (let (source (source-for context))
          (when (and source (not (hash-key? seen source)))
            (hash-put! seen source #t)
            (set! rows (cons `(gxc: ,(path-strip-extension (substring source (string-length root) (string-length source)))) rows)))))
      (parameterize
          ((current-expander-context (make-top-context))
           (current-expander-module-import
            (lambda (path (reload? #f))
              (let* ((context (native-import path reload?)) (source (source-for context)))
                (if (and source (not (equal? (path-normalize source) (path-normalize (module-context-path context)))))
                  (native-import source reload?) context)))))
        (for-each
          (lambda (identity)
            (let (relative (library-relative-source
                            (string->symbol (substring (symbol->string identity) 1 (string-length (symbol->string identity))))))
              (for-each-build-module
                (core-import-module (path-expand relative root)) visit)))
          bootstrap-roots))
      (reverse rows))))
