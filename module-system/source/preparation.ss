;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Prepare compiler input from selected local sources; never import or run them.
(import (only-in :clan/poo/object .o .ref .slot?)
        (only-in :yuanxu/module-system/source/role-forms module-publication-role-imports)
        ;; Compiler bindings emitted by this preparer are real bootstrap inputs.
        (only-in :yuanxu/module-system/source/declaration include-module-body)
        (only-in :yuanxu/module-system/source/config-prelude)
        (only-in :yuanxu/module-system/source/module-prelude)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/expander current-expander-module-import expander-context-id syntax-e
                 core-read-module/sexp core-library-package-plist syntax->datum
                 core-resolve-library-module-path
                 module-context? module-context-path prelude-context? prelude-context-path)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/admission)
(export yuanxu-prepare-module-publication yuanxu-write-module-publication
        yuanxu-prepare-module-build-source yuanxu-prepare-module-tool-source
        yuanxu-prepare-module-retained-source
        yuanxu-prepare-module-private-source call-with-module-compiler-inputs)
(def (source-metadata source key)
  (let (entry (assq key (yuanxu-module-source-ref-metadata source)))
    (and entry (cdr entry))))
(def (module-compiler-identity path)
  (module-source-observe read-module-compiler-identity path))
(def (default-role-prelude? prelude)
  ;; core-read-module/sexp has already resolved native prelude references. Do
  ;; not compare its result to the spelling originally written in gerbil.pkg.
  (cond
    ((not prelude) #t)
    ((or (module-context? prelude) (prelude-context? prelude))
     (memq (expander-context-id prelude) '(gerbil/core tao3k/yuanxu/prelude)))
    ((string? prelude)
     (ormap (lambda (identity)
              (with-catch (lambda (_missing) #f)
                (lambda () (equal? prelude (core-resolve-library-module-path identity)))))
       '(:gerbil/core :tao3k/yuanxu/prelude)))
    (else (memq (syntax->datum prelude) '(:gerbil/core :tao3k/yuanxu/prelude)))))
(def (read-module-compiler-identity path (text #f))
  ;; Native package/header resolution, without core-import-module or expansion.
  (when (current-module-source-observer)
    ((current-module-source-observer) 'compiler-identity-reads 1))
  (let-values (((prelude identity namespace body) (core-read-module/sexp path)))
    ;; Do not return the read syntax. Interpreted slot closures retain their
    ;; lexical frame, including unused sibling bindings, until their owner dies.
    (list (cond ((module-context? prelude) (module-context-path prelude))
                ((prelude-context? prelude) (prelude-context-path prelude))
                (else prelude))
          identity namespace
          (or (not text)
              ;; The native reader has already resolved and checked the entire
              ;; module. Inclusion only needs to know whether it stripped a
              ;; leading header, not convert and parse the whole body again.
              (call-with-input-string text
                (lambda (port)
                  (not (memq (read port) '(prelude: namespace: package:))))))
          (default-role-prelude? prelude))))
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

(def (yuanxu-prepare-module-publication source-value
                                          style-policy: (policy yuanxu-default-module-style-policy)
                                          admit-context: (context-current! void))
  (unless (and (yuanxu-module-source-ref? source-value)
               (eq? (yuanxu-module-source-ref-kind source-value) 'local))
    (error "publication preparation requires a selected local SourceRef" source-value))
  (let* ((owner (source-metadata source-value 'module-id))
         (root (or (source-metadata source-value 'module-root) (source-metadata source-value 'module-tree-root)))
         (path (yuanxu-module-source-ref-value source-value))
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
                         yuanxu-module-allowed-entrypoint-roles))
            (error "stale prepared Module publication" owner path))
          (context-current!))
        ;; The interpreter redirects original sources through its admitted reader;
        ;; standalone compiler input imports adjacent prepared role projections.
        ;; The existing POO prelude is one SDK-owned weak binding frame. Do not
        ;; copy its full export set into every generated interface's strong
        ;; import table. Explicit role/import bindings still override the prelude.
        ;; A contributor's custom prelude keeps the original explicit imports.
        (def shared-prelude? (list-ref compiler-info 4))
        (def (publication-forms imports)
          (append
           (if shared-prelude?
             '(prelude: :yuanxu/module-system/source/config-prelude)
             (list 'prelude: (car compiler-info)))
           (list 'package: (substring id-text 0 (- (string-length id-text) (string-length suffix)))
                 'namespace: (caddr compiler-info)
                 `(import ,@(if shared-prelude? '() '((except-in :clan/poo/object .def)))
                          (only-in :yuanxu/module-system/source/declaration .def define-module-build-binding)
                          ,@imports))
           (if (hash-key? texts (path-expand "build.ss" root))
             (list '(define-module-build-binding Build)) '())
           (list `(include ,path))))
        (.o bind-these: #f source: source-value identity: owner binding: name
            compiler-identity: (cadr compiler-info)
            source-inputs:
            (append package-sources prelude-inputs
                    (map (lambda (role)
                           (let (file (path-expand (string-append (symbol->string role) ".ss") root))
                             (cons file (and (hash-key? texts file) (hash-ref texts file)))))
                         yuanxu-module-allowed-entrypoint-roles))
            role-sources: (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles)
            build-source: (let (file (path-expand "build.ss" root))
                            (and (hash-key? texts file) file))
            namespace: (caddr compiler-info) prelude: (car compiler-info)
            admit-current: current!
            reader-forms: (publication-forms
                           (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles))
            compiler-forms: (publication-forms
                             (map (lambda (role) (string-append "./" (symbol->string role) ".ss")) roles))))))
(def (yuanxu-write-module-publication prepared output)
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
                          (yuanxu-prepare-module-build-source path (.ref prepared 'admit-current))))
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
(def (yuanxu-prepare-module-build-source source-path context-current!)
  (prepare-build-source source-path context-current! #f))
;; Only SDK-observed tool sources use native inclusion. In particular the
;; declaration compiler cannot import its own include-module-body binding.
(def (yuanxu-prepare-module-tool-source source-path context-current!)
  (prepare-build-source source-path context-current! #t))
;; Explicit non-Module roots keep their ordinary Scheme body and exports.
;; They do not acquire Module role imports or Config semantics by basename.
(def (yuanxu-prepare-module-retained-source source-path context-current!)
  (prepare-build-source source-path context-current! #t))
(def (prepare-build-source source-path context-current! tool?)
  (context-current!)
  (let* ((text (module-source-read source-path))
         (packages (package-source-snapshot source-path)))
    (let-values (((prelude id namespace header-free? default-prelude?)
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
      (.o bind-these: #f path: source-path compiler-identity: id admit-current: current!
          source-inputs: (cons (cons source-path text) packages)
          compiler-forms:
          (append (cond
                    ((and (not tool?)
                          (member (path-strip-directory source-path)
                            '("types.ss" "objects.ss" "func.ss" "config.ss" "build.ss"))
                          default-prelude?)
                     '(prelude: :yuanxu/module-system/source/module-prelude))
                    (prelude (list 'prelude: prelude))
                    (else '()))
                  (list 'package: (path-strip-trailing-directory-separator
                                   (path-directory (symbol->string id)))
                        'namespace: namespace)
                  (cond
                    ((and tool? header-free?) (list `(include ,source-path)))
                    ((string=? (path-strip-directory source-path) "config.ss")
                    (list '(import (only-in :yuanxu/module-system/source/declaration
                                            include-module-body export-role-config))
                          `(include-module-body ,source-path)
                          '(export-role-config Config)))
                    (else
                     (list '(import (only-in :yuanxu/module-system/bootstrap/body-inclusion include-module-body))
                           `(include-module-body ,source-path)))))))))

;;; The native expander supplies actual imports. Only owner-confined regular
;;; sources may join the build declaration closure; no directory scan is needed.
(def (yuanxu-prepare-module-private-source root source-path context-current!)
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
    (yuanxu-prepare-module-build-source path context-current!)))

;; The native compiler and Make coordinator both call the SDK's public import
;; parameter. Redirect only the selected prepared inputs, preserving their native
;; identity and original included syntax. Make still owns original source targets
;; and dependency/product timestamps; generated frames are not new build targets.
(def (call-with-module-compiler-inputs entries action)
  (call-with-temporary-directory "yuanxu-compiler-roles"
    (lambda (directory)
      (def native-import (current-expander-module-import))
      (def inputs (make-hash-table))
      ;; Reuse the publication's admitted role inventory. Ordinary retained
      ;; libraries and private helpers retain their native source import path.
      (def roles (make-hash-table))
      (for-each
        (lambda (entry)
          (def input (.ref entry 'input))
          (when (.slot? input 'role-sources)
            (hash-put! roles (path-normalize (.ref entry 'path)) #t)
            (for-each (lambda (path) (hash-put! roles (path-normalize path) #t))
              (.ref input 'role-sources)))) entries)
      (for-each
        (lambda (entry)
          (def original (path-normalize (.ref entry 'path)))
          (def input (.ref entry 'input))
          (def identity (.ref input 'compiler-identity))
          (def target
            (path-expand (string-append (symbol->string identity) ".ss") directory))
          ((.ref input 'admit-current))
          (create-directory* (path-directory target))
          (call-with-output-file (list path: target truncate: #f)
            (lambda (port)
              (for-each (lambda (form) (write form port) (newline port))
                (.ref input 'compiler-forms))))
          (def row (list input target identity))
          (hash-put! inputs original row)
          (hash-put! inputs (string->symbol (string-append ":" (symbol->string identity))) row))
        (filter (lambda (entry) (hash-key? roles (path-normalize (.ref entry 'path)))) entries))
      (def (import-input path (reload? #f))
        (def datum (syntax-e path))
        (def row
          (hash-get inputs
            (if (string? datum) (path-normalize (path-expand datum)) datum)))
        (if (not row) (native-import path reload?)
          (let ((input (car row)) (target (cadr row)) (identity (caddr row)))
            (when reload? (error "prepared compiler input requires a fresh source epoch" datum))
            ((.ref input 'admit-current))
            (let (context (native-import target #f))
              (unless (eq? identity (expander-context-id context))
                (error "prepared compiler identity changed" datum identity))
              ((.ref input 'admit-current))
              context))))
      (parameterize ((current-expander-module-import import-input)) (action)))))
