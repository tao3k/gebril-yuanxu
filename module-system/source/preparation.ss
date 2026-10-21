;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Prepare compiler input from selected local sources; never import or run them.
(import (only-in :clan/poo/object .o .ref)
        (only-in :core/module-system/source/role-forms module-publication-role-imports)
        ;; Compiler bindings emitted by this preparer are real bootstrap inputs.
        (only-in :core/module-system/source/declaration include-module-body)
        (only-in :core/module-system/source/config-prelude)
        (only-in :gerbil/expander core-read-module/sexp core-library-package-plist syntax->datum)
        :core/module-system/source/objects
        :core/module-system/source/admission)
(export poo-flow-prepare-module-publication poo-flow-write-module-publication
        poo-flow-prepare-module-build-source poo-flow-prepare-module-tool-source
        poo-flow-prepare-module-retained-source
        poo-flow-prepare-module-private-source)
(def (source-metadata source key)
  (let (entry (assq key (poo-flow-module-source-ref-metadata source)))
    (and entry (cdr entry))))
(def (module-compiler-identity path)
  (module-source-observe read-module-compiler-identity path))
(def (read-module-compiler-identity path (header-free-text #f))
  ;; Native package/header resolution, without core-import-module or expansion.
  (when (current-module-source-observer)
    ((current-module-source-observer) 'compiler-identity-reads 1))
  (let-values (((prelude identity namespace body) (core-read-module/sexp path)))
    (when (and header-free-text
               (not (equal? (syntax->datum body)
                            (call-with-input-string header-free-text read-all))))
      (error "compiler tool inclusion requires a header-free source body" path))
    ;; Do not return the read syntax. Interpreted slot closures retain their
    ;; lexical frame, including unused sibling bindings, until their owner dies.
    (list prelude identity namespace)))
(def (package-source-snapshot path)
  ;; Observe the native reader's ancestor lookup, not a second package resolver.
  ;; Negative entries matter when a closer gerbil.pkg is added later.
  (let loop ((directory (path-directory path)) (entries '()))
    (let* ((file (path-expand "gerbil.pkg" directory))
           (kind (module-source-type file)))
      (if kind
        (let* ((text (module-source-read file))
               (datum (call-with-input-string text read))
               (expected (if (eof-object? datum) '() datum)))
          (unless (equal? expected (core-library-package-plist directory #t))
            (error "native package metadata cache is stale; use a fresh compiler context" file))
          (reverse (cons (cons file text) entries)))
        (let (trimmed (path-strip-trailing-directory-separator directory))
          (if (or (string-empty? trimmed) (string=? directory trimmed))
            (reverse (cons (cons file #f) entries))
            (loop (path-directory trimmed) (cons (cons file #f) entries))))))))
(def (package-snapshot-current? entries)
  (module-source-observe check-package-snapshot-current? entries))
(def (check-package-snapshot-current? entries)
  ;; Sibling sources have different negative ancestor lists but share the same
  ;; positive gerbil.pkg entry. Reuse its pure byte/SDK-identity check inside
  ;; the EXISTING read window; do not reparse it once per source guard.
  (andmap (lambda (entry) (module-source-observe check-package-entry-current? entry)) entries))
(def (check-package-entry-current? entry)
  (if (cdr entry)
    (and (eq? (module-source-type (car entry)) 'regular)
         (equal? (cdr entry) (module-source-read (car entry)))
         (let* ((datum (call-with-input-string (cdr entry) read))
                (expected (if (eof-object? datum) '() datum)))
           (equal? expected (core-library-package-plist (path-directory (car entry)) #t))))
    (not (module-source-type (car entry)))))

;; Return only the binding identity. Interpreted slot/guard closures retain
;; enclosing lexical frames, including unused sibling bindings. The persistent
;; preparation must not own a second parsed interface tree beside its bytes.
(def (publication-source-binding path text)
  (let* ((forms (call-with-input-string text read-all))
         (declarations (filter (lambda (form) (and (pair? form) (eq? (car form) '.def))) forms)))
    (unless (and (= (length declarations) 1)
                 (andmap (lambda (form) (and (pair? form) (memq (car form) '(import .def)))) forms))
      (error "interface.ss must contain one Module .def and optional explicit external imports" path))
    (let (binding (cadr (car declarations)))
      (if (pair? binding) (car binding) binding))))

(def (poo-flow-prepare-module-publication source-value
                                          style-policy: (policy poo-flow-default-module-style-policy)
                                          admit-context: (context-current! void))
  (unless (and (poo-flow-module-source-ref? source-value)
               (eq? (poo-flow-module-source-ref-kind source-value) 'local))
    (error "publication preparation requires a selected local SourceRef" source-value))
  (let* ((owner (source-metadata source-value 'module-id))
         (root (or (source-metadata source-value 'module-root) (source-metadata source-value 'module-tree-root)))
         (path (poo-flow-module-source-ref-value source-value))
         (texts (make-hash-table)))
    (unless (and (symbol? owner) (string? root) (string? path)
                 (string=? (path-expand path) (path-expand "interface.ss" root)))
      (error "publication source owner/root/entrypoint association is missing" source-value))
    ((.ref policy 'validate) policy owner root
     (lambda (file)
       (let (text (module-source-read file))
         (hash-put! texts file text) text)))
      (let* ((name (publication-source-binding path (hash-ref texts path)))
             (package-sources (package-source-snapshot path))
             (compiler-info (module-compiler-identity path))
             (prelude-inputs
              (let (prelude (car compiler-info))
                (if (and (string? prelude) (string=? (path-extension prelude) ".ss"))
                  (list (cons prelude (module-source-read prelude))) '())))
             (id-text (symbol->string (cadr compiler-info)))
             (suffix "/interface")
             (imports (module-publication-role-imports root (cut hash-key? texts <>)))
             (roles (map (lambda (name) (string->symbol (path-strip-extension (path-strip-directory name)))) imports)))
        (unless (and (symbol? name) (string-suffix? suffix id-text))
          (error "invalid Module binding or native compiler identity" path name compiler-info))
        (def (current!)
          (context-current!)
          (module-source-admit-current! prelude-inputs "stale Module prelude source")
          ;; Unchanged role/header bytes plus native package lookup determine
          ;; identity; do not parse interface.ss again on every guard.
          (unless (and (package-snapshot-current? package-sources)
                       (andmap
                         (lambda (role)
                           (let (file (path-expand
                                        (string-append (symbol->string role) ".ss") root))
                             (if (hash-key? texts file)
                               (equal? (hash-ref texts file) (module-source-read file))
                               (not (module-source-type file)))))
                         poo-flow-module-allowed-entrypoint-roles))
            (error "stale prepared Module publication" owner path))
          (context-current!))
        ;; The interpreter redirects original sources through its admitted reader;
        ;; standalone compiler input imports adjacent prepared role projections.
        ;; The existing POO prelude is one SDK-owned weak binding frame. Do not
        ;; copy its full export set into every generated interface's strong
        ;; import table. Explicit role/import bindings still override the prelude.
        ;; A contributor's custom prelude keeps the original explicit imports.
        (def shared-prelude?
          (or (not (car compiler-info))
              (eq? (syntax->datum (car compiler-info)) ':gerbil/core)))
        (def (publication-forms imports)
          (append
           (if shared-prelude?
             '(prelude: :core/module-system/source/config-prelude)
             (list 'prelude: (car compiler-info)))
           (list 'package: (substring id-text 0 (- (string-length id-text) (string-length suffix)))
                 'namespace: (caddr compiler-info)
                 `(import ,@(if shared-prelude? '() '((except-in :clan/poo/object .def)))
                          (only-in :core/module-system/source/declaration .def define-module-build-binding)
                          ,@imports))
           (if (hash-key? texts (path-expand "build.ss" root))
             (list '(define-module-build-binding Build)) '())
           (list `(include ,path))))
        (.o source: source-value identity: owner binding: name
            compiler-identity: (cadr compiler-info)
            source-inputs:
            (append package-sources prelude-inputs
                    (map (lambda (role)
                           (let (file (path-expand (string-append (symbol->string role) ".ss") root))
                             (cons file (and (hash-key? texts file) (hash-ref texts file)))))
                         poo-flow-module-allowed-entrypoint-roles))
            role-sources: (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles)
            build-source: (let (file (path-expand "build.ss" root))
                            (and (hash-key? texts file) file))
            namespace: (caddr compiler-info) prelude: (car compiler-info)
            admit-current: current!
            reader-forms: (publication-forms
                           (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles))
            compiler-forms: (publication-forms
                             (map (lambda (role) (string-append "./" (symbol->string role) ".ss")) roles))))))
(def (poo-flow-write-module-publication prepared output)
  ;; Materialization belongs to source preparation, never to the syntax expander.
  (unless (string=? (path-strip-directory output) "interface.ss")
    (error "prepared compiler entry must retain the interface.ss basename" output))
  (when (module-source-type output)
    (error "prepared compiler output must be a fresh artifact" output))
  ((.ref prepared 'admit-current))
  ;; Materialize the same native role frames used by the reader; never copy
  ;; bare config.ss into a compiler tree where its role prelude would be lost.
  (let (roles (map (lambda (path)
                    (cons (path-expand (path-strip-directory path) (path-directory output))
                          (poo-flow-prepare-module-build-source path (.ref prepared 'admit-current))))
                  (.ref prepared 'role-sources)))
    (for-each (lambda (role)
                (when (module-source-type (car role))
                  (error "prepared role output must be a fresh artifact" (car role)))) roles)
    (create-directory* (path-directory output))
    (for-each (lambda (role)
                (call-with-output-file (list path: (car role) truncate: #t)
                  (lambda (port)
                    (for-each (lambda (form) (write form port) (newline port))
                              (.ref (cdr role) 'compiler-forms))))) roles))
  (create-directory* (path-directory output))
  (call-with-output-file (list path: output truncate: #t)
    (lambda (port)
      (display ";;; Generated from an admitted Module source; do not edit.\n" port)
      (for-each (lambda (form) (write form port) (newline port)) (.ref prepared 'compiler-forms))))
  ((.ref prepared 'admit-current))
  output)

;;; Native reader projection, not an evaluator or a compiler dependency scanner.
;;; A relocatable build tree retains native identity/namespace and the reader's
;;; headers. Internal native inclusion retains the original source locations.
(def (poo-flow-prepare-module-build-source source-path context-current!)
  (prepare-build-source source-path context-current! #f))
;; Only SDK-observed tool sources use native inclusion. In particular the
;; declaration compiler cannot import its own include-module-body binding.
(def (poo-flow-prepare-module-tool-source source-path context-current!)
  (prepare-build-source source-path context-current! #t))
;; Explicit non-Module roots keep their ordinary Scheme body and exports.
;; They do not acquire Module role imports or Config semantics by basename.
(def (poo-flow-prepare-module-retained-source source-path context-current!)
  (prepare-build-source source-path context-current! #t))
(def (prepare-build-source source-path context-current! tool?)
  (context-current!)
  (let* ((text (module-source-read source-path))
         (packages (package-source-snapshot source-path)))
    (let-values (((prelude id namespace)
                  (apply values (read-module-compiler-identity source-path (and tool? text)))))
      ;; Header extraction owns and releases the temporary syntax frame. The
      ;; persistent POO projection retains only metadata and guarded source bytes;
      ;; native include/expansion remains deferred to its original demand.
      ;; Native identity is determined by the exact header bytes and ancestor
      ;; package resolution observed above. Revalidate both (including the native
      ;; package cache), rather than reparse the entire unchanged module body.
      (def (current!)
        (context-current!)
        (unless (equal? text (module-source-read source-path))
          (error "stale prepared build source" source-path 'source-bytes-changed))
        (unless (package-snapshot-current? packages)
          (error "stale prepared build source" source-path 'package-metadata-changed))
        (context-current!))
      (.o path: source-path compiler-identity: id admit-current: current!
          source-inputs: (cons (cons source-path text) packages)
          compiler-forms:
          (append (cond
                    ((and (not tool?) (string=? (path-strip-directory source-path) "config.ss")
                          (or (not prelude) (eq? (syntax->datum prelude) ':gerbil/core)))
                     '(prelude: :core/module-system/source/config-prelude))
                    (prelude (list 'prelude: prelude))
                    (else '()))
                  (list 'package: (path-strip-trailing-directory-separator
                                   (path-directory (symbol->string id)))
                        'namespace: namespace)
                  (cond
                    (tool? (list `(include ,source-path)))
                    ((string=? (path-strip-directory source-path) "config.ss")
                    (list '(import (only-in :core/module-system/source/declaration
                                            include-module-body export-role-config))
                          `(include-module-body ,source-path)
                          '(export-role-config Config)))
                    (else
                     (list '(import (only-in :core/module-system/source/declaration include-module-body))
                           `(include-module-body ,source-path)))))))))

;;; The native expander supplies actual imports. Only owner-confined regular
;;; sources may join the build declaration closure; no directory scan is needed.
(def (poo-flow-prepare-module-private-source root source-path context-current!)
  (let* ((base (path-normalize (path-expand root)))
         (prefix (string-append (path-strip-trailing-directory-separator base) "/"))
         (raw (path-expand source-path))
         (path (path-normalize raw)))
    (unless (and (string-prefix? prefix path) (string=? (path-extension path) ".ss"))
      (error "private source escapes its Module owner" root source-path))
    ;; Check the unresolved spelling before normalization can erase a symlink.
    ;; Native relative imports may retain ./ and internal ../ components.
    (unless (string-prefix? prefix raw)
      (error "private source must use its admitted owner path" root source-path))
    (let walk ((directory base) (parts (string-split (substring raw (string-length prefix) (string-length raw)) #\/)))
      (unless (pair? parts) (error "invalid private source path" source-path))
      (let ((part (car parts)))
        (cond
         ((string=? part ".") (walk directory (cdr parts)))
         ((string=? part "..")
          (let (parent (path-directory (path-strip-trailing-directory-separator directory)))
            (unless (or (equal? (path-normalize parent) base) (string-prefix? prefix (path-normalize parent)))
              (error "private source escapes its Module owner" source-path))
            (walk parent (cdr parts))))
         (else
          (unless (module-source-name? part) (error "invalid private source path" source-path))
          (let (next (path-expand part directory))
            (unless (eq? (module-source-type next) (if (pair? (cdr parts)) 'directory 'regular))
              (error "private source is missing, non-regular or a symlink" next))
            (when (pair? (cdr parts)) (walk next (cdr parts))))))))
    (poo-flow-prepare-module-build-source path context-current!)))
