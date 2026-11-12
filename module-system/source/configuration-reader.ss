;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Evaluate Build and configuration bindings with their existing source guards.
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/expander current-expander-context make-top-context
                 current-expander-module-import current-expander-compile
                 current-expander-eval eval-syntax syntax-e)
        (only-in :clan/poo/object .ref)
        :tao3k/yuanxu/module-system/source/admission
        :tao3k/yuanxu/module-system/source/preparation
        :tao3k/yuanxu/module-system/source/reader-evaluation
        :tao3k/yuanxu/module-system/source/import-provenance
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module))
(export module-prepared-source-binding)

(def (module-prepared-source-binding prepared binding (related '())
                                    context-current!: (context-current! void)
                                    role-imports?: (role-imports? #f)
                                    shared-contexts: (shared-contexts #f)
                                    shared-inputs: (shared-inputs #f)
                                    private-sources: (private-sources '())
                                    import-provenance: (import-provenance #f)
                                    source-inputs: (observe-inputs void))
  (let* ((inputs (append (cons prepared related) private-sources))
         (directory (make-temporary-file-name "configuration-reader-"))
         (prefix (symbol->string (gensym 'configuration-reader-)))
         (wrappers (make-hash-table)) (artifact-paths (make-hash-table-eq))
         (owned (make-hash-table)) (completed (make-hash-table-eq))
         (gerbil-import (current-expander-module-import)))
    (defvalues (compile evaluate) (reader-evaluation-observers owned completed))
    ;; An admitted outer reader already owns this exact Gerbil catalogue/index.
    ;; Share its structural maps, not a source-currentness or admission result.
    ;; Standalone role readers still acquire their own runtime compiler closure.
    (defvalues (tool-contexts tool-paths tool-dependencies tool-observations compiler-contexts)
      (if import-provenance (apply values import-provenance) (module-import-provenance)))
    (def (current!)
      (parameterize ((current-module-source-phase 'configuration-current))
        (context-current!)
        (call-with-module-source-read-cache
          (lambda ()
            (module-source-admit-current! (hash->list tool-observations) "compiler tool source changed")
            (for-each (lambda (input) ((.ref input 'admit-current))) inputs)))))
    (def (write-input! input)
      ;; Exact admitted compiler identities also name symbol-relative imports.
      ;; This is an index of captured inputs, not another source resolver.
      (hash-put! artifact-paths (.ref input 'compiler-identity) (path-normalize (.ref input 'path)))
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
            (register-reader-wrapper! owned wrapper #t)
            (call-with-output-file wrapper
              (lambda (port)
                (write 'package: port) (display " " port)
                (write (path-strip-trailing-directory-separator
                         (path-directory (symbol->string (.ref input 'compiler-identity)))) port)
                (newline port)
                (write 'namespace: port) (display " " port)
                (write (string-append prefix "/" (path-strip-extension (path-strip-directory wrapper))) port)
                (newline port)
                (for-each (lambda (form) (write form port) (newline port))
                  (append (reader-body (.ref input 'compiler-forms)
                            (if (and role-imports? (eq? input prepared))
                              (list `(import :clan/poo/object
                                             ,@(map (cut .ref <> 'path) related))) '()))
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
                     (let* ((requested (syntax-e path))
                            (text (and (symbol? requested) (symbol->string requested)))
                            (runtime-id (and text (> (string-length text) 1)
                                            (char=? (string-ref text 0) #\:)
                                            (string->symbol (substring text 1 (string-length text)))))
                            (source (or (and (string? requested) (path-normalize requested))
                                        (and runtime-id (hash-get artifact-paths runtime-id))))
                            (target (and source (hash-get wrappers source))))
                       (cond
                         ((pair? target)
                          (when reload? (error "shared publication context reload requires a fresh reader"))
                          ((.ref (car target) 'admit-current))
                          (cdr target))
                         (target (gerbil-import target reload?))
                         ;; Keep this interceptor active while expanding our own
                         ;; generated entry. Otherwise its relative role imports
                         ;; escape to the runtime original-path registry, and a
                         ;; fresh source epoch can silently reuse an old value.
                         ((and (string? path) (string-prefix? directory path))
                          (gerbil-import path reload?))
                         ((and (string? path) (hash-get tool-paths (path-normalize path)))
                          => (lambda (context)
                               (when reload? (error "compiler tool reload requires a fresh configuration context"))
                               (unless (captured-import-context? compiler-contexts context)
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
                            (parameterize ((current-expander-module-import gerbil-import))
                              (gerbil-import path #f))))
                         (else (parameterize ((current-expander-module-import gerbil-import))
                                 (gerbil-import path reload?))))))))
               (eval-syntax `(import ,(hash-ref wrappers (path-normalize (.ref prepared 'path)))))
               (eval-syntax binding)))
         ;; A returned closure can use these imports later. Hand its actual
         ;; source support back to the enclosing Graph/role owner; checking it
         ;; only during evaluation would lose deferred Build-only dependencies.
         ;; Normalize support by path, rejecting inconsistent expected bytes.
         ;; This temporary projection index is discarded before returning; it
         ;; stores no check result and never avoids a later physical read.
         (let (observations (make-hash-table))
           (record-source-observations! observations (hash->list tool-observations))
           (for-each (lambda (input)
                       (record-source-observations! observations (.ref input 'source-inputs))) inputs)
           (observe-inputs (hash->list observations)))
         (current!)
         (release-reader-expansions! completed)
         result))
     (lambda () (remove-reader-tree directory)))))
