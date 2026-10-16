;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Prepare compiler input from selected local sources; never import or run them.
(import (only-in :clan/poo/object .o .ref)
        (only-in :gerbil/expander core-read-module/sexp core-library-package-plist)
        :core/module-system/source/objects
        :core/module-system/source/admission)
(export poo-flow-prepare-module-publication poo-flow-write-module-publication
        poo-flow-prepare-module-build-source)
(def (source-metadata source key)
  (let (entry (assq key (poo-flow-module-source-ref-metadata source)))
    (and entry (cdr entry))))
(def (module-compiler-identity path)
  ;; Native package/header resolution, without core-import-module or expansion.
  (let-values (((prelude identity namespace body) (core-read-module/sexp path)))
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
  (andmap (lambda (entry)
            (if (cdr entry)
              (and (eq? (module-source-type (car entry)) 'regular)
                   (equal? (cdr entry) (module-source-read (car entry))))
              (not (module-source-type (car entry))))) entries))

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
    (let* ((forms (call-with-input-string (hash-ref texts path) read-all))
           (declarations (filter (lambda (form) (and (pair? form) (eq? (car form) '.def))) forms)))
      (unless (and (= (length declarations) 1)
                   (andmap (lambda (form) (and (pair? form) (memq (car form) '(import .def)))) forms))
        (error "interface.ss must contain one Module .def and optional explicit external imports" path))
      (let* ((declaration (car declarations))
             (binding (cadr declaration))
             (name (if (pair? binding) (car binding) binding))
             (package-sources (package-source-snapshot path))
             (compiler-info (module-compiler-identity path))
             (id-text (symbol->string (cadr compiler-info)))
             (suffix "/interface")
             (roles (filter (lambda (role)
                              (hash-key? texts (path-expand (string-append (symbol->string role) ".ss") root)))
                            '(types func objects config))))
        (unless (and (symbol? name) (string-suffix? suffix id-text))
          (error "invalid Module binding or native compiler identity" path name compiler-info))
        (def (current!)
          (context-current!)
          (unless (and (package-snapshot-current? package-sources)
                       (equal? compiler-info (module-compiler-identity path))
                       (andmap (lambda (role)
                                 (let (file (path-expand (string-append (symbol->string role) ".ss") root))
                                   (if (hash-key? texts file)
                                     (equal? (hash-ref texts file) (module-source-read file))
                                     (not (module-source-type file)))))
                               poo-flow-module-allowed-entrypoint-roles))
            (error "stale prepared Module publication" owner path))
          (context-current!))
        (.o source: source-value identity: owner binding: name
            compiler-identity: (cadr compiler-info)
            source-inputs:
            (append package-sources
                    (map (lambda (role)
                           (let (file (path-expand (string-append (symbol->string role) ".ss") root))
                             (cons file (and (hash-key? texts file) (hash-ref texts file)))))
                         poo-flow-module-allowed-entrypoint-roles))
            role-sources: (map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles)
            namespace: (caddr compiler-info)
            admit-current: current!
            ;; Include preserves the author's syntax locations and native reader.
            ;; Only the wrapper imports this internal .def binding.
            compiler-forms:
            (append
             (if (car compiler-info) (list 'prelude: (car compiler-info)) '())
             (list 'package: (substring id-text 0 (- (string-length id-text) (string-length suffix)))
                   'namespace: (caddr compiler-info)
                   `(import (except-in :clan/poo/object .def)
                            (only-in :core/module-system/source/declaration .def)
                            ,@(map (lambda (role) (path-expand (string-append (symbol->string role) ".ss") root)) roles))
                   `(include ,path))))))))
(def (poo-flow-write-module-publication prepared output)
  ;; Materialization belongs to source preparation, never to the syntax expander.
  (unless (string=? (path-strip-directory output) "interface.ss")
    (error "prepared compiler entry must retain the interface.ss basename" output))
  (when (module-source-type output)
    (error "prepared compiler output must be a fresh artifact" output))
  ((.ref prepared 'admit-current))
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
  (context-current!)
  (let* ((text (module-source-read source-path))
         (packages (package-source-snapshot source-path))
         (compiler-info (module-compiler-identity source-path)))
    (let-values (((prelude id namespace _body) (core-read-module/sexp source-path)))
      (def (current!)
        (context-current!)
        (unless (and (equal? text (module-source-read source-path))
                     (package-snapshot-current? packages)
                     (equal? compiler-info (module-compiler-identity source-path)))
          (error "stale prepared build source" source-path))
        (context-current!))
      (.o path: source-path compiler-identity: id admit-current: current!
          source-inputs: (cons (cons source-path text) packages)
          compiler-forms:
          (append (if prelude (list 'prelude: prelude) '())
                  (list 'package: (path-strip-trailing-directory-separator
                                   (path-directory (symbol->string id)))
                        'namespace: namespace)
                  (list '(import (only-in :core/module-system/source/declaration include-module-body))
                        `(include-module-body ,source-path)))))))
