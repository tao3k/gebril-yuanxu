;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Prepare compiler input from selected local sources; never import or run them.
(import (only-in :yuanxu/module-system/building/products
                 build-output-directory current-build-source-directory current-build-compiler-options
                 invalidate-build-products! artifact-files static-product-path
                 call-with-selected-output-lock selected-output-source-directory)
        (only-in :yuanxu/module-system/building/source-package
                 call-with-build-input-path module-build-source-path)
        (only-in :clan/poo/object .o .ref .ref/cached .slot? object? object-protocol
                 object-%instance object-%precedence-list object-construction-current?)
        (only-in :clan/poo/slot-observation without-observation)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :yuanxu/module-system/source/deferred-declaration module-deferred-role-exports)
        (only-in :yuanxu/module-system/source/role-forms module-publication-role-imports module-interface-form? module-role-file)
        ;; Compiler bindings emitted by this preparer are real bootstrap inputs.
        (only-in :yuanxu/module-system/source/declaration include-module-body)
        (only-in :yuanxu/module-system/source/config-prelude)
        (only-in :yuanxu/module-system/source/module-prelude)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :gerbil/runtime/gambit current-readtable)
        (only-in :gerbil/runtime/syntax __*readtable*)
        (only-in :gerbil/expander current-expander-module-import expander-context-id syntax-e
                 core-read-module/sexp core-read-module-package core-library-package-plist __module-pkg-cache syntax->datum
                 core-resolve-library-module-path
                 module-context? module-context-path prelude-context? prelude-context-path)
        (only-in :gerbil/expander/module __module-registry)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module build-module-dependencies)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/admission)
(export build-target-name module-source-package-prefix module-source-package-info
        yuanxu-prepare-module-publication yuanxu-write-module-publication
        yuanxu-prepare-module-build-source yuanxu-prepare-module-tool-source
        yuanxu-prepare-module-retained-source
        yuanxu-prepare-module-private-source call-with-module-compiler-inputs module-compiler-source-input
        module-compiler-source-input-compatible? module-source-input-state module-compiler-source-owner?)
;; Only the existing compiler-input owner installs this dynamic source index.
;; std/make temporarily removes srcdir while checking dependency timestamps.
;; That ambient search path is not the selected compiler source association.
(def compiler-source-inputs (make-parameter #f))
(defstruct compiler-input (value state owner entry) final: #t)
(def (compiler-source-ref inputs key)
  (let (row (and inputs (hash-get inputs key)))
    (and row (compiler-input-value row))))
(def (module-compiler-source-owner? owner path)
  ;; Inherited producer functions cannot transfer their parent's authority to a
  ;; derived Graph. This is receiver identity, not a namespace or purity flag.
  (let (inputs (compiler-source-inputs))
    (or (not inputs)
        (begin
          (require-read-route! 'compiler-source inputs #f)
          (let (row (hash-get inputs (path-normalize path)))
            (and row (eq? owner (compiler-input-owner row))))))))
(def (module-compiler-source-input-compatible? path checker)
  ;; Inspect the existing selected index. Another closure needs its OWN actual
  ;; constructor association from the projection owner, never a user slot flag.
  (with-catch (lambda (_unsupported) #f)
    (lambda ()
      (without-observation
        (lambda ()
          (def inputs (compiler-source-inputs))
          (when inputs (require-read-route! 'compiler-source inputs #f))
          (def row (and inputs (hash-get inputs (path-normalize (path-expand path)))))
          (def input (and row (compiler-input-value row)))
          (or (not input)
              (and (object? input) (object-%precedence-list input)
                   (not (object-protocol input)) (object-%instance input)
                   (begin
                     (require-read-route! 'compiler-source #f (object-%instance input))
                     (let ((actual (.ref/cached input 'admit-current (lambda () #f)))
                           (identity (.ref/cached input 'compiler-identity (lambda () #f))))
                       (and (symbol? identity)
                            (or (eq? checker actual)
                                (and (compiler-input-state row)
                                     ((compiler-input-state row) input actual identity)))))))))))))
(def (module-source-input-state value checker ready?)
  ;; Called at the actual constructor/derived-copy boundary. This binds state,
  ;; not a successful byte check. Compiler-owner indices retain the association.
  (and checker (object-construction-current?)
    (let (metadata (module-source-object-policy (list value)))
      (lambda ()
        (and (metadata) (object-%instance value) (object-%precedence-list value)
             (begin
               (require-read-route! 'compiler-source #f (object-%instance value))
               (eq? checker (.ref/cached value 'admit-current (lambda () #f))))
             (ready?))))))
(def (compiler-role-paths entries)
  ;; Role identity comes from the admitted publication, not a basename or a
  ;; caller-supplied strategy flag. The same inventory owns both routing/writing.
  (def roles (make-hash-table))
  (for-each
    (lambda (entry)
      (def input (.ref entry 'input))
      (when (.slot? input 'role-sources)
        (hash-put! roles (path-normalize (.ref entry 'path)) #t)
        (for-each (lambda (path) (hash-put! roles (path-normalize path) #t))
          (.ref input 'role-sources)))) entries)
  roles)
(def (module-compiler-source-input path)
  (let* ((inputs (compiler-source-inputs))
         (input (compiler-source-ref inputs (path-normalize (path-expand path)))))
    (and input (begin
                 (module-source-measure-operation 'compiler-input-lookup
                   (lambda () ((.ref input 'admit-current))))
                 input))))

(def (source-metadata source key)
  (let (entry (assq key (yuanxu-module-source-ref-metadata source)))
    (and entry (cdr entry))))
(def (module-compiler-identity path source-root)
  (module-source-observe read-module-compiler-identity path #f #t source-root))
(def (default-role-prelude? prelude)
  ;; core-read-module/sexp has already resolved runtime prelude references. Do
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
(def (read-module-compiler-identity path (text #f) (classify-role? #t) (source-root #f))
  ;; Runtime package/header resolution, without core-import-module or expansion.
  (when (current-module-source-observer)
    ((current-module-source-observer) 'compiler-identity-reads 1))
  (let-values (((prelude identity namespace body) (core-read-module/sexp path)))
    (def prelude-path
      (cond ((module-context? prelude) (module-context-path prelude))
            ((prelude-context? prelude) (prelude-context-path prelude))
            (else prelude)))
    ;; A warm bootstrap binds the installed interface for the same language.
    ;; Retain its original source observation only when the declared source
    ;; owner can authenticate that language through the native projection.
    (def owned-prelude-source
      (and source-root (string? prelude-path)
           (string=? (path-extension prelude-path) ".ssi")
           (or (module-context? prelude) (prelude-context? prelude))
           (eq? (expander-context-id prelude) 'tao3k/yuanxu/prelude)
           (module-build-source-path prelude source-root)))
    ;; Do not return the read syntax. Interpreted slot closures retain their
    ;; lexical frame, including unused sibling bindings, until their owner dies.
    (list (or owned-prelude-source prelude-path)
          identity namespace
          (or (not text)
              ;; The runtime reader has already resolved and checked the entire
              ;; module. Inclusion only needs to know whether it stripped a
              ;; leading header, not convert and parse the whole body again.
              (call-with-input-string text
                (lambda (port)
                  (not (memq (read port) '(prelude: namespace: package:))))))
          (and classify-role?
               (module-source-measure-operation 'reader-role-prelude
                 (lambda () (default-role-prelude? prelude)))))))
;; Captured from the official expander lookup at preparation, never a second
;; package resolver/cache. Public source-inputs remain path/byte pairs.
(defstruct package-source (path text expected cached) final: #t)
(def (package-source-inputs entries)
  (map (lambda (entry) (cons (package-source-path entry) (package-source-text entry))) entries))
(def (package-source-snapshot path)
  ;; Observe the runtime reader's ancestor lookup, not a second package resolver.
  ;; Negative entries matter when a closer gerbil.pkg is added later.
  (package-directory-snapshot (path-directory path)))
(def (module-source-package-info directory)
  (def entries (package-directory-snapshot directory))
  (unless (package-snapshot-current? entries)
    (error "Gerbil package inputs changed" directory))
  (let find-owner ((remaining entries))
    (and (pair? remaining)
         (let (entry (car remaining))
           (if (package-source-text entry)
             (list (path-directory (package-source-path entry))
                   (package-source-cached entry) (package-source-text entry))
             (find-owner (cdr remaining)))))))
(def (module-source-package-prefix directory)
  ;; Reuse Gerbil's ancestor/package namespace and the existing source snapshot.
  ;; No Module is imported or evaluated, and no directory is enumerated.
  (def path (path-expand "interface.ss" directory))
  (def snapshot (package-source-snapshot path))
  (let-values (((_prelude _namespace package) (core-read-module-package path #f #f)))
    (unless (and (string? package) (> (string-length package) 0))
      (error "module source root has no native package namespace" directory))
    (unless (package-snapshot-current? snapshot)
      (error "module source root package identity changed" directory))
    (string-append package "/")))
(def (package-directory-snapshot directory)
  ;; This is immutable preparation data. Only an enclosing source observation
  ;; window may share it. The open observer route retains each original read.
  (if (current-module-source-observer)
    (read-package-directory-snapshot directory)
    (module-source-observe read-package-directory-snapshot directory)))
(def (read-package-directory-snapshot directory)
  (let (file (path-expand "gerbil.pkg" directory))
    (if (module-source-type file)
      (let* ((text (module-source-read file))
             (datum (call-with-input-string text read))
             (expected (if (eof-object? datum) '() datum))
             (cached (core-library-package-plist directory #t)))
        (unless (equal? expected cached)
          (error "runtime package metadata cache is stale; use a fresh compiler context" file))
        (list (make-package-source file text expected cached)))
      (let* ((entry (make-package-source file #f #f #f))
             (trimmed (path-strip-trailing-directory-separator directory)))
        (cons entry
          (if (or (string-empty? trimmed) (string=? directory trimmed))
            '()
            (package-directory-snapshot (path-directory trimmed))))))))
(def (package-snapshot-current? entries)
  (module-source-observe check-package-snapshot-current? entries))
(def (check-package-snapshot-current? entries)
  ;; Sibling sources have different negative ancestor lists but share the same
  ;; positive gerbil.pkg entry. Reuse its pure byte/Gerbil-identity check inside
  ;; the EXISTING read window; do not reparse it once per source guard.
  (andmap (lambda (entry) (module-source-observe check-package-entry-current? entry)) entries))
(def (check-package-entry-current? entry)
  (def path (package-source-path entry))
  (if (package-source-text entry)
    (and (eq? (module-source-type path) 'regular)
         (equal? (package-source-text entry) (module-source-read path))
         (equal? (package-source-expected entry)
                 (core-library-package-plist (path-directory path) #t)))
    (not (module-source-type path))))
(def (package-sources-read-only? entries)
  ;; Read ONLY the installed expander's existing cache. A cold/replaced entry
  ;; falls back before the shared interval; never call its file reader here.
  (require-read-route! 'compiler-package __module-pkg-cache #f)
  (andmap (lambda (entry)
    (or (not (package-source-text entry))
        (let (value (hash-get __module-pkg-cache (path-directory (package-source-path entry))))
          (and (eq? value (package-source-cached entry))
               (source-datum? (package-source-expected entry))
               (equal? value (package-source-expected entry)))))) entries))
;; Native write on these data cannot dispatch a user object's printer. Cycles
;; and opaque objects use the original writer behind the callback boundary.
(def (source-datum? value (ancestors '()))
  (cond
    ((or (null? value) (boolean? value) (number? value) (char? value)
         (string? value) (symbol? value) (keyword? value)) #t)
    ((memq value ancestors) #f)
    ((pair? value)
     (let (next (cons value ancestors))
       (and (source-datum? (car value) next) (source-datum? (cdr value) next))))
    ((vector? value)
     (let (next (cons value ancestors))
       (andmap (lambda (item) (source-datum? item next)) (vector->list value))))
    (else #f)))
(def (write-source-datum value port)
  (if (source-datum? value) (write value port)
      (call-with-module-source-callback (lambda () (write value port)))))

;; The binding check and the closed role classifier consume the same private
;; datums. No datum is passed to the native reader or an author callback.
(def (publication-source-binding path forms)
  (let (declarations (filter (lambda (form) (and (pair? form) (eq? (car form) '.def))) forms))
    (unless (and (= (length declarations) 1)
                 (andmap (cut module-interface-form? <> forms) forms))
      (error "interface.ss must contain one Module .def with optional imports and local re-exports" path))
    (let (binding (cadr (car declarations)))
      (if (pair? binding) (car binding) binding))))

(def (yuanxu-prepare-module-publication source-value
                                          style-policy: (policy yuanxu-default-module-style-policy)
                                          admit-context: (context-current! void)
                                          capture: (capture #f))
  (unless (and (yuanxu-module-source-ref? source-value)
               (eq? (yuanxu-module-source-ref-kind source-value) 'local))
    (error "publication preparation requires a selected local SourceRef" source-value))
  (let* ((owner (source-metadata source-value 'module-id))
         (declared-owner (or (source-metadata source-value 'declaration-id) owner))
         (root (or (source-metadata source-value 'module-root) (source-metadata source-value 'module-tree-root)))
         (path (yuanxu-module-source-ref-value source-value))
         (texts (make-hash-table)))
    (unless (and (symbol? owner) (string? root) (string? path)
                 (string=? (path-expand path) (path-expand "interface.ss" root)))
      (error "publication source owner/root/entrypoint association is missing" source-value))
    ((.ref policy 'validate) policy declared-owner root
     (lambda (file)
       (let (text (module-source-read file))
         (hash-put! texts file text) text)))
      (let* ((interface-text (hash-ref texts path))
             (share-forms? (and (not (current-module-source-observer))
                                (eq? (current-readtable) __*readtable*)))
             (interface-forms
               (module-source-measure-operation 'reader-interface-datums
                 (lambda () (call-with-input-string interface-text read-all))))
             (name (publication-source-binding path interface-forms))
             (package-sources (package-source-snapshot path))
             (compiler-info (module-compiler-identity path (source-metadata source-value 'kernel-root)))
             (prelude-inputs
              (let (prelude (car compiler-info))
                (if (and (string? prelude) (string=? (path-extension prelude) ".ss"))
                  (list (cons prelude (module-source-read prelude))) '())))
             (id-text (symbol->string (cadr compiler-info)))
             (suffix "/interface")
             (imports (module-publication-role-imports root (cut hash-key? texts <>)))
             (roles (map (lambda (name) (string->symbol (path-strip-extension (path-strip-directory name)))) imports)))
        (when (and (source-metadata source-value 'declaration-id)
                   (not (eq? owner (cadr compiler-info))))
          (error "selected native module identity differs from its source" owner (cadr compiler-info) path))
        (unless (and (symbol? name) (string-suffix? suffix id-text))
          (error "invalid Module binding or runtime compiler identity" path name compiler-info))
        (def (check-source!)
          (module-source-admit-current! prelude-inputs "stale Module prelude source")
          ;; Unchanged role/header bytes plus runtime package lookup determine
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
            (error "stale prepared Module publication" owner path)))
        ;; The native no-context route is the source checker itself, not a
        ;; wrapper annotated as pure. Open contexts retain both actual calls.
        (def current!
          (if (eq? context-current! void) check-source!
            (lambda ()
              (call-with-module-source-callback context-current!)
              (check-source!)
              (call-with-module-source-callback context-current!))))
        ;; The interpreter redirects original sources through its admitted reader;
        ;; standalone compiler input imports adjacent prepared role projections.
        ;; The existing POO prelude is one Gerbil-owned weak binding frame. Do not
        ;; copy its full export set into every generated interface's strong
        ;; import table. Explicit role/import bindings still override the prelude.
        ;; A contributor's custom prelude keeps the original explicit imports.
        (def shared-prelude? (list-ref compiler-info 4))
        (def private-import-roles '())
        (def deferred-roles
          (and shared-prelude?
            (module-deferred-role-exports interface-text
              (map (lambda (role)
                     (cons role (hash-ref texts
                       (path-expand (string-append (symbol->string role) ".ss") root)))) roles)
              interface-forms: (and share-forms? (not (current-module-source-observer))
                                    (eq? (current-readtable) __*readtable*) interface-forms)
              private-import: (lambda (role)
                                (unless (memq role private-import-roles)
                                  (set! private-import-roles (cons role private-import-roles)))))))
        (def (publication-forms imports (deferred #f) (compiled? #f))
          (let (resolver
                 (and deferred compiled?
                     `(lambda ()
                        (lambda (role names)
                          (module-import-role-values
                            (case role
                              ,@(map (lambda (row)
                                       `((,(car row))
                                         ',(string->symbol
                                            (string-append ":"
                                              (substring id-text 0 (- (string-length id-text) (string-length "interface")))
                                              (symbol->string (car row)))))) deferred)
                              (else (error "unknown published role" role)))
                            names)))))
          (append
           (if shared-prelude?
             '(prelude: :yuanxu/module-system/source/config-prelude)
             (list 'prelude: (car compiler-info)))
           (list 'package: (substring id-text 0 (- (string-length id-text) (string-length suffix)))
                 'namespace: (caddr compiler-info)
                 `(import ,@(if shared-prelude? '() '((except-in :clan/poo/object .def)))
                          (only-in :yuanxu/module-system/source/declaration .def define-module-build-binding)
                          ,@(if deferred
                              `((only-in :yuanxu/module-system/source/deferred-declaration
                                         include-deferred-declaration
                                         ,@(if compiled? '(module-import-role-values) '())))
                              '())
                          ,@(if (and deferred compiled? (pair? roles))
                              `((for-template
                                 ,@(map (lambda (role)
                                          (string-append "./" (symbol->string role) ".ss")) roles)))
                              '())
                          ,@imports))
           (if (hash-key? texts (path-expand "build.ss" root))
             (list '(define-module-build-binding Build)) '())
           (list (if deferred `(include-deferred-declaration ,path ,deferred ,resolver) `(include ,path))))))
        ;; Retained preparation and guard closures own bytes, not this parse tree.
        (set! interface-forms #f)
        (def construction-intact? (object-construction-current?))
        (def value
          (.o bind-these: #f path source: source-value identity: owner binding: name
            compiler-identity: (cadr compiler-info)
            source-inputs:
            (append (package-source-inputs package-sources) prelude-inputs
                    (map (lambda (role)
                           (let (file (path-expand (string-append (symbol->string role) ".ss") root))
                             (cons file (and (hash-key? texts file) (hash-ref texts file)))))
                         yuanxu-module-allowed-entrypoint-roles))
            role-sources: (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles)
            build-source: (let (file (path-expand "build.ss" root))
                            (and (hash-key? texts file) file))
            namespace: (caddr compiler-info) prelude: (car compiler-info)
            admit-current: current!
            deferred-roles: deferred-roles
            deferred-import-sources:
            (if deferred-roles
              (filter-map (lambda (role)
                            (and (memq role private-import-roles)
                                 (path-expand (module-role-file role) root))) roles)
              '())
            reader-forms: (if deferred-roles
                           (publication-forms '() deferred-roles)
                           (publication-forms
                             (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles)))
            compiler-forms: (if deferred-roles
                             (publication-forms '() deferred-roles #t)
                             (publication-forms
                               (map (lambda (role) (string-append "./" (symbol->string role) ".ss")) roles)))))
        (if capture
          (let ((checker (and construction-intact? (object-construction-current?)
                              (eq? context-current! void) check-source!))
                (ready? (lambda () (package-sources-read-only? package-sources))))
            (capture value checker path ready? (module-source-input-state value checker ready?)))
          value))))
(def (yuanxu-write-module-publication prepared output)
  ;; Materialization belongs to source preparation, never to the syntax expander.
  (unless (string=? (path-strip-directory output) "interface.ss")
    (error "prepared compiler entry must retain the interface.ss basename" output))
  (when (module-source-type output)
    (error "prepared compiler output must be a fresh artifact" output))
  ((.ref prepared 'admit-current))
  ;; Materialize the same runtime role frames used by the reader; never copy
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
                    (for-each (lambda (form) (write-source-datum form port) (newline port))
                              (.ref (cdr role) 'compiler-forms))))) roles))
  (create-directory* (path-directory output))
  (call-with-output-file (list path: output truncate: #t)
    (lambda (port)
      (display ";;; Generated from an admitted Module source; do not edit.\n" port)
      (for-each (lambda (form) (write-source-datum form port) (newline port)) (.ref prepared 'compiler-forms))))
  ((.ref prepared 'admit-current))
  output)

;;; Runtime reader projection, not an evaluator or a compiler dependency scanner.
;;; A relocatable build tree retains runtime identity/namespace and the reader's
;;; headers. Internal runtime inclusion retains the original source locations.
(def (yuanxu-prepare-module-build-source source-path context-current! capture: (capture #f))
  (prepare-build-source source-path context-current! #f capture))
;; Only Gerbil-observed tool sources use runtime inclusion. In particular the
;; declaration compiler cannot import its own include-module-body binding.
(def (yuanxu-prepare-module-tool-source source-path context-current! capture: (capture #f))
  (prepare-build-source source-path context-current! #t capture))
;; Explicit non-Module roots keep their ordinary Scheme body and exports.
;; They do not acquire Module role imports or Config semantics by basename.
(def (yuanxu-prepare-module-retained-source source-path context-current! capture: (capture #f))
  (prepare-build-source source-path context-current! #t capture))
(def (prepare-build-source source-path context-current! tool? capture)
  (call-with-module-source-callback context-current!)
  (let* ((text (module-source-read source-path))
         (packages (package-source-snapshot source-path)))
    (let-values (((prelude id namespace header-free? default-prelude?)
                  (apply values
                    (read-module-compiler-identity source-path (and tool? text) (not tool?)))))
      ;; Header extraction owns and releases the temporary syntax frame. The
      ;; persistent POO projection retains only metadata and guarded source bytes;
      ;; runtime include/expansion remains deferred to its original demand.
      ;; Runtime identity is determined by the exact header bytes and ancestor
      ;; package resolution observed above. Revalidate both (including the runtime
      ;; package cache), rather than reparse the entire unchanged module body.
      (def (check-source!)
        ;; Only these byte/package observations are pure. Reuse the existing
        ;; window for the package's regular-file probe and byte read; leave
        ;; both owning Context calls outside it, as either can run author code.
        ;; Independent calls still open a fresh window and read current bytes.
        (call-with-module-source-read-cache
          (lambda ()
            (unless (equal? text (module-source-read source-path))
              (error "stale prepared build source" source-path 'source-bytes-changed))
            (unless (package-snapshot-current? packages)
              (error "stale prepared build source" source-path 'package-metadata-changed)))))
      (def admit-current
        (if (eq? context-current! void) check-source!
          (lambda ()
            (call-with-module-source-callback context-current!)
            (check-source!)
            (call-with-module-source-callback context-current!))))
      (def path source-path)
      (def compiler-identity id)
      (def construction-intact? (object-construction-current?))
      (def value
        (.o bind-these: #f path compiler-identity admit-current
          source-inputs: (cons (cons source-path text) (package-source-inputs packages))
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
                           `(include-module-body ,source-path)))))))
      (if capture
        (let ((checker (and construction-intact? (object-construction-current?)
                            (eq? context-current! void) check-source!))
              (ready? (lambda () (package-sources-read-only? packages))))
          (capture value checker path ready? (module-source-input-state value checker ready?)))
        value))))

;;; The runtime expander supplies actual imports. Only owner-confined regular
;;; sources may join the build declaration closure; no directory scan is needed.
(def (yuanxu-prepare-module-private-source root source-path context-current! capture: (capture #f))
  (let* ((base (path-normalize (path-expand root)))
         (prefix (string-append (path-strip-trailing-directory-separator base) "/"))
         (raw (path-expand source-path))
         (path (path-normalize raw)))
    (unless (and (string-prefix? prefix path) (string=? (path-extension path) ".ss"))
      (error "private source escapes its Module owner" root source-path))
    ;; Check the unresolved spelling before normalization can erase a symlink.
    ;; Runtime relative imports may retain ./ and internal ../ components.
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
    (yuanxu-prepare-module-build-source path context-current! capture: capture)))

;; The runtime compiler and Make coordinator both call the Gerbil's public import
;; parameter. Redirect only the selected prepared inputs, preserving their runtime
;; identity and original included syntax. Make still owns original source targets
;; and dependency/product timestamps; generated frames are not new build targets.
(def (call-with-module-compiler-inputs entries action unified?: (unified? #f)
         recorded-entries: (recorded-entries '())
         source-reads: (source-reads for-each-batch) source-state: (source-state #f)
         source-owner: (source-owner #f) source-import: (source-import compiler-import/independent)
         refuse-input-context: (refuse-input-context #f))
  ;; Own the association before a source route or role preparation can invoke
  ;; a currentness callback. Restoring this parameter also restores nested owners.
  (def selected-sources (make-hash-table))
  ;; The projection owner checks the complete footprint before and after
  ;; this extent. Enrollment is not admission: each lookup below still
  ;; physically rechecks its selected input before exposing it. Do not
  ;; repeat each input's enclosing Context check while only indexing paths.
  (module-source-measure-operation 'compiler-input-enrollment
    (lambda ()
      (for-each (lambda (entry)
        (hash-put! selected-sources (path-normalize (.ref entry 'path))
                   (make-compiler-input (.ref entry 'input) source-state source-owner entry))) entries)))
  (parameterize ((compiler-source-inputs selected-sources))
    (let (roles (compiler-role-paths entries))
      (if unified? (call-with-selected-source-view entries roles action source-reads source-import
                     refuse-input-context)
        (begin
          (unless (null? recorded-entries)
            (let* ((libdir (build-output-directory))
                   (view (selected-output-source-directory libdir)))
              (artifact-files (map (cut .ref <> 'compiler-identity) recorded-entries) libdir #f)
              (create-directory* view)
              (prepare-compiler-view-entries! recorded-entries roles source-reads libdir view preserve-unrecorded?: #t)))
          (call-with-role-compiler-inputs entries roles action source-reads source-import))))))
(def (for-each-batch entries action) (action entries))
(def (compiler-import/independent _entry _input _importer _target _identity action)
  (call-with-module-source-callback action))
(def (call-with-role-compiler-inputs entries roles action (source-reads for-each-batch)
                                      (source-import compiler-import/independent))
  (def (run directory materialize?)
      (def gerbil-import (current-expander-module-import))
      (def prior-catalog (hash-copy __module-registry))
      (def staged-prefix
        (string-append (path-strip-trailing-directory-separator
                         (path-normalize directory)) "/"))
      (def (restore-staged-imports!)
        ;; Importing prepared roles installs both path and identity aliases in
        ;; Gerbil's catalog. They must not outlive their temporary source tree.
        ;; Preserve unrelated imports and restore the exact prior contexts,
        ;; including nested compiler extents, without evaluating a module again.
        (def seen (make-hash-table-eq))
        (def consumers (make-hash-table-eq))
        (def affected (make-hash-table-eq))
        (def pending '())
        (def (enroll! context)
          (when (and (string? (module-context-path context))
                     (string-prefix? staged-prefix (module-context-path context)))
            (set! pending (cons context pending)))
          (for-each
            (lambda (dependency)
              (when (module-context? dependency)
                (hash-update! consumers dependency (cut cons context <>) '())))
            (build-module-dependencies context)))
        ;; A stable-path importer can still retain a staged child. Traverse the
        ;; native graph once, then propagate invalidation to its consumers.
        ;; The extent-local reverse index is discarded after cleanup: O(V+E),
        ;; with no successful source check or alternate module catalog cached.
        (hash-for-each
          (lambda (key context)
            (when (module-context? key)
              (for-each-build-module key enroll! seen))
            (when (module-context? context)
              (for-each-build-module context enroll! seen))) __module-registry)
        (let propagate ()
          (when (pair? pending)
            (let (context (car pending))
              (set! pending (cdr pending))
              (unless (hash-key? affected context)
                (hash-put! affected context #t)
                (for-each (lambda (consumer) (set! pending (cons consumer pending)))
                  (hash-ref consumers context '()))))
            (propagate)))
        (def staged-keys '())
        (hash-for-each
          (lambda (key context)
            (when (or (hash-key? affected context) (hash-key? affected key))
              (set! staged-keys (cons key staged-keys)))) __module-registry)
        (for-each
          (lambda (key)
            (if (hash-key? prior-catalog key)
              (hash-put! __module-registry key (hash-ref prior-catalog key))
              (hash-remove! __module-registry key))) staged-keys))
      (def inputs (make-hash-table))
      ;; Reuse the publication's admitted role inventory. Ordinary retained
      ;; libraries and private helpers retain their runtime source import path.
      (source-reads
       (filter (lambda (entry) (hash-key? roles (path-normalize (.ref entry 'path)))) entries)
       (lambda (batch)
        (for-each
        (lambda (entry)
          (def original (path-normalize (.ref entry 'path)))
          (def input (.ref entry 'input))
          (def identity (.ref input 'compiler-identity))
          (def target
            (path-expand (string-append (symbol->string identity) ".ss") directory))
          (module-source-measure-operation 'compiler-role-inventory
            (lambda () ((.ref input 'admit-current))))
          (when materialize?
            (call-with-module-source-callback
              (lambda ()
                (create-directory* (path-directory target))
                (call-with-output-file (list path: target truncate: #f)
                  (lambda (port)
                    (for-each (lambda (form) (write-source-datum form port) (newline port))
                      (.ref input 'compiler-forms)))))))
          (def row (list input target identity entry))
          (hash-put! inputs original row)
          (hash-put! inputs (path-normalize target) row)
          (hash-put! inputs (string->symbol (string-append ":" (symbol->string identity))) row))
        batch)))
      (def (import-input path (reload? #f))
        (def datum (syntax-e path))
        (def key (if (string? datum) (path-normalize (path-expand datum)) datum))
        (def row
          (or (hash-get inputs key)
              ;; Native Make needs an input timestamp at its full target name.
              ;; That existing descriptor is NOT another library source. Resolve
              ;; its enrolled input through the original Gerbil path/cache.
              (let* ((selected-inputs (compiler-source-inputs))
                     (selected (and (string? key) selected-inputs (hash-get selected-inputs key)))
                     (input (and selected (compiler-input-value selected))))
                (and input (not (equal? key (path-normalize (.ref input 'path))))
                     (list input (.ref input 'path) (.ref input 'compiler-identity)
                           (compiler-input-entry selected))))))
        (if (not row) (gerbil-import path reload?)
          (let ((input (car row)) (target (cadr row)) (identity (caddr row)))
            (when reload? (error "prepared compiler input requires a fresh source epoch" datum))
            (source-import (cadddr row) input gerbil-import target identity
              (lambda ()
                (module-source-measure-operation 'compiler-import-before
                  (lambda () ((.ref input 'admit-current))))
                (let (context (gerbil-import target #f))
                  (unless (eq? identity (expander-context-id context))
                    (error "prepared compiler identity changed" datum identity))
                  (module-source-measure-operation 'compiler-import-after
                    (lambda () ((.ref input 'admit-current))))
                  context))))))
      (dynamic-wind
        void
        (lambda () (parameterize ((current-expander-module-import import-input)) (action)))
        (lambda () (when materialize? (restore-staged-imports!)))))
  (if (current-build-source-directory)
    ;; The stable role frames are already materialized by the selected view.
    ;; Reuse them for original-path imports too, instead of a second temp copy.
    (run (current-build-source-directory) #f)
    (call-with-temporary-directory "yuanxu-compiler-roles" (cut run <> #t))))

(def (build-target-name identity package-prefix
                        (language (and (equal? package-prefix "yuanxu")
                                       'tao3k/yuanxu/prelude)))
  ;; One root-owned language file has an explicit runtime package identity.
  ;; Callers still verify its actual source path and prepared identity.
  (if (and language (eq? identity language))
    "prelude"
    (let ((name (symbol->string identity))
          (prefix (if (string-empty? package-prefix) "" (string-append package-prefix "/"))))
    (unless (string-prefix? prefix name)
      (error "compiler identity is outside the build package prefix" identity package-prefix))
    (let (relative (substring name (string-length prefix) (string-length name)))
      (unless (andmap module-source-name? (string-split relative #\/))
        (error "compiler identity is not a relative build target" identity))
      relative))))

;; The downstream output environment owns this materialization. Stable source
;; contents are reused; every invocation still admits original source snapshots.
(def (call-with-selected-source-view entries roles action source-reads source-import refuse-input-context)
  (def libdir (build-output-directory))
  (call-with-selected-output-lock libdir
    (lambda ()
      (module-source-measure-operation 'compiler-view-extent
        (lambda ()
          (call-with-selected-source-view/locked entries roles action source-reads source-import
            libdir refuse-input-context))))))
(def (call-with-selected-source-view/locked entries roles action source-reads source-import libdir
                                       refuse-input-context)
  (def identities (map (lambda (entry) (.ref entry 'compiler-identity)) entries))
  (artifact-files identities libdir #f)
  (def view (selected-output-source-directory libdir))
  (create-directory* view)
  ;; The view must not retain a previous selection's source fallback. Reuse
  ;; only our generated frames; unrelated/user files and symlinks are refused.
  (def wanted
    (map (lambda (entry)
           (path-expand
             (string-append (build-target-name (.ref entry 'compiler-identity) "") ".ss") view)) entries))
  (def (prune directory)
    (for-each
      (lambda (name)
        (def path (path-expand name directory))
        (case (module-source-type path)
          ((directory) (prune path))
          ((regular)
           (unless (and (string-suffix? ".ss" name)
                        (call-with-input-file path
                          (lambda (in) (let (line (read-line in))
                            (and (string? line) (string-prefix? ";; yuanxu-input " line))))))
             (error "unowned source in selected compiler view" path))
           (unless (member (path-normalize path) wanted) (delete-file path)))
          (else (error "non-regular source-view entry" path))))
      (directory-files directory)))
  (prune view)
  ;; Enroll aliases in the existing extent-owned input association before any
  ;; guard/callback runs. Nested compiler extents restore their own association.
  (for-each
    (lambda (entry)
      ;; view is canonical and build-target-name admits only relative identity
      ;; components. Its child directories do not exist until materialization.
      (def target (path-expand
                    (string-append (build-target-name (.ref entry 'compiler-identity) "") ".ss") view))
      (def input (.ref entry 'input))
      (def previous (compiler-source-ref (compiler-source-inputs) target))
      (when (and previous (not (eq? previous input)))
        (error "compiler input alias collides with selected source" target))
      (hash-put! (compiler-source-inputs) target
        (hash-ref (compiler-source-inputs) (path-normalize (.ref entry 'path))))) entries)
  (prepare-compiler-view-entries! entries roles source-reads libdir view)
  (def (compile)
    (parameterize ((current-build-source-directory view))
      (call-with-role-compiler-inputs entries roles action source-reads source-import)))
  (if refuse-input-context
    (call-with-build-input-path libdir compile refuse-input-context source-roots: (list view))
    (call-with-build-input-path libdir compile source-roots: (list view))))

(def (prepare-compiler-view-entries! entries roles source-reads libdir view
                                        preserve-unrecorded?: (preserve-unrecorded? #f))
  (source-reads entries
   (lambda (batch)
    (for-each
    (lambda (entry)
      (def input (.ref entry 'input))
      (module-source-measure-operation 'compiler-view-before
        (lambda () ((.ref input 'admit-current))))
      (def identity (.ref entry 'compiler-identity))
      (def name (build-target-name identity ""))
      (def target (path-expand (string-append name ".ss") view))
      (let walk ((directory view) (parts (string-split name #\/)))
        (when (pair? (cdr parts))
          (let* ((next (path-expand (car parts) directory)) (kind (module-source-type next)))
            (when (and kind (not (eq? kind 'directory)))
              (error "selected source view component is not a directory" next))
            (create-directory* next)
            (walk next (cdr parts)))))
      (def kind (module-source-type target))
      (when (and kind (not (eq? kind 'regular)))
        (error "selected source target is not a regular file" target))
      (def previous (and kind (module-source-read target)))
      (when (and previous (not (string-prefix? ";; yuanxu-input " previous)))
        (error "unowned source in selected compiler view" target))
      ;; A local producer leaves an unrecorded native marker under Make's
      ;; existing freshness policy. Absence of a descriptor grants no reuse
      ;; to a later unified consumer.
      (when (or (not preserve-unrecorded?) previous
                (not (module-source-type (static-product-path identity libdir))))
        (let ()
          (def content
            (call-with-output-string
              (lambda (out)
                ;; One escaped datum in a comment binds bytes, options and tools to
                ;; this compiler input without storing any admission verdict.
                (display ";; yuanxu-input " out)
                (write-source-datum (list (.ref input 'source-inputs) (.ref entry 'options)
                             (gerbil-version-string) (gerbil-home) (current-build-compiler-options)
                             (map (lambda (key) (cons key (getenv key #f)))
                               '("GERBIL_GSC" "GERBIL_GCC" "GERBIL_BUILD_OPTIMIZED" "GERBIL_BUILD_DEBUG" "GERBIL_BUILD_RELEASE"))) out)
                (newline out)
                ;; Ordinary libraries retain only the EXISTING Make input stamp.
                ;; Their source is neither copied as a module nor included/expanded
                ;; here. The native importer above receives their original path.
                (if (hash-key? roles (path-normalize (.ref entry 'path)))
                  (for-each (lambda (form) (write-source-datum form out) (newline out))
                            (.ref input 'compiler-forms))
                  ;; Make reads target identity before asking the importer to expand
                  ;; the original library. Publish its package in the native header.
                  (begin
                    (display "package: " out)
                    (write-source-datum
                      (path-strip-trailing-directory-separator (path-directory name)) out)
                    (newline out))))))
          (unless (equal? previous content)
            ;; A crash after invalidation cannot reuse the previous native marker.
            (call-with-module-source-callback
              (lambda ()
                (invalidate-build-products! (list identity) libdir)
                (create-directory* (path-directory target))
                (call-with-output-file (list path: target truncate: #t) (lambda (out) (display content out))))))))
      (module-source-measure-operation 'compiler-view-after
        (lambda () ((.ref input 'admit-current))))) batch))))
