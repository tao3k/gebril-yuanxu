prelude: :gerbil/core
;;; SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
;;; Build-time only: preserve the compiler-owned runtime dependency graph.
(import :gerbil/compiler
        :gerbil/expander
        (only-in :std/list/list delete-duplicates/hash append-map)
        (only-in :std/encoding/json write-json read-json current-json-read-options make-JSONReadOptions)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-name? module-source-type))
(import (only-in "program-activation.ss" program-activation-form))
(export yuanxu-project-compiled-program yuanxu-clean-compiled-program)

(def program-stub-file "program__exe.scm")
(def program-manifest-file "program.json")
(def program-observation-file "metadata-modules.dat")
(def program-metadata-directory "metadata")
(def program-schema "gerbil-scheme-rust.aot-program.v1")

;; The versioned compiler adapter lives here, never in a downstream Rust
;; parser. These are the same native graph operations used by compile-exe.
(extern namespace: gxc
  find-runtime-module-deps find-static-module-file static-module-name gerbil-runtime-modules
  current-compile-gsc-options gcc-ld-options apply-generate-loader
  compile-executable-module current-compile-invoke-gsc current-compile-output-dir
  current-compile-keep-scm current-compile-identifiers current-compile-context
  module-id->path-string)

;; The compiler's link closure includes runtime: declarations made while
;; expanding macros. Only its executable loader plan describes activation.
;; Do not initialize a linked role merely because expansion registered it.
(def (program-loader-imports context)
  (def (loads form)
    (match form
      (['begin forms ...] (append-map loads forms))
      (['load-module path] [path])
      (else (error "unsupported native compiler loader plan" form))))
  (parameterize ((current-expander-context context))
    (loads (apply-generate-loader (module-context-code context)))))

(def (program-bootstrap-contexts root contexts)
  (def seen (make-hash-table-eq))
  (def (walk context)
    (def id (expander-context-id context))
    (unless (hash-key? seen id)
      (hash-put! seen id #t)
      (cond
        ((module-context? context)
         (when (core-context-prelude context) (walk (core-context-prelude context)))
         (for-each (lambda (path)
                     (let (dependency (hash-get contexts path))
                       (unless dependency (error "loader dependency is outside link closure" id path))
                       (walk dependency)))
                   (program-loader-imports context)))
        ((prelude-context? context)
         (for-each walk (filter module-context? (prelude-context-import context)))))))
  (walk root)
  seen)

(def (system-context? context)
  (let (id (symbol->string (expander-context-id context)))
    (or (string-prefix? "gerbil/" id) (string-prefix? "std/" id))))

;; Namespace ordering and installed object availability are different facts.
;; A tools module may ship only .scm; compile that source through the ordinary
;; programme archive path instead of claiming a reusable installed AOT object.
(def (installed-aot? id scm)
  (and (or (string-prefix? "gerbil/" id) (string-prefix? "std/" id))
       (file-exists? (string-append (path-strip-extension scm) ".c"))
       (file-exists? (string-append (path-strip-extension scm) ".o"))))

;; Template imports carry runtime values without eager initialization. Follow
;; their native Contexts, including their runtime dependency closure, instead
;; of relying on which macro carriers happened to initialize in the observer.
(def (program-template-contexts roots)
  (def seen (make-hash-table-eq))
  (def result '())
  (def (template-source entry)
    (cond
     ;; A native runtime: import carries a direct Context, rather than a
     ;; binding-bearing import set. Preserve that native representation.
     ((module-context? entry) entry)
     ((and (import-set? entry) (negative? (import-set-phi entry)))
      (import-set-source entry))
     ((and (module-import? entry) (negative? (module-import-phi entry)))
      (module-export-context (module-import-source entry)))
     (else #f)))
  (def (walk context deferred?)
    (def id (expander-context-id context))
    (unless (hash-key? seen id)
      (hash-put! seen id #t)
      ;; The native closure also contains Prelude Contexts. Its public driver
      ;; accepts a Module Context, not a Prelude in the same unchecked slots.
      (when (module-context? context)
        (for-each (lambda (dependency) (walk dependency deferred?))
                  (find-runtime-module-deps context))
        (for-each (lambda (entry)
                    (let (source (template-source entry))
                      (when (module-context? source) (walk source #t))))
                  (module-context-import context)))
      (when deferred? (set! result (cons context result)))))
  (for-each (lambda (context) (walk context #f)) roots)
  (reverse result))

(def (yuanxu-project-compiled-program entry output-dir (runtime-imports [])
       gsc-options: (gsc-options []))
  (let* ((native-gsc-options
           gsc-options)
         (output (path-expand "program" output-dir))
         (context (import-module (string->symbol (string-append ":" (symbol->string entry)))))
         (dependencies (find-runtime-module-deps context))
         ;; Registered contexts preserve nested module identity. Resolving
         ;; the loader's string as a new library can read its Gambit .scm and
         ;; manufacture an unrelated context (e.g. std/ffi~C-struct).
         (by-path (list->hash-table
                    (filter-map (lambda (ctx)
                                  (let (id (expander-context-id ctx))
                                    (and id (cons (module-id->path-string id) ctx))))
                                (cons context dependencies))))
         (bootstrap (program-bootstrap-contexts context by-path))
         (contexts
          (filter (lambda (ctx)
                    (not (string-prefix? "gerbil/core" (symbol->string (expander-context-id ctx)))))
                  (append dependencies (list context))))
         (ids (delete-duplicates/hash
               (append gerbil-runtime-modules
                       ;; Preserve compile-exe's system-before-user link order.
                       (map (lambda (ctx) (symbol->string (expander-context-id ctx)))
                            (append (filter system-context? contexts)
                                    (filter (lambda (ctx) (not (system-context? ctx)))
                                            contexts)))))))
    ;; The entry module's main must return normally without entering an event
    ;; loop. Its ordinary exports become callable after shared runtime setup.
    ;; Consume the existing Context. compile-exe's filename wrapper would
    ;; reopen an SSI as source; std/make has already compiled this module.
    (parameterize ((current-compile-invoke-gsc #f)
                   (current-compile-output-dir output-dir)
                   (current-compile-keep-scm #t)
                   (current-compile-gsc-options native-gsc-options)
                   (current-compile-identifiers (make-hash-table-eq))
                   (current-compile-context `((project-compiled-program ,entry))))
      (compile-executable-module context
        [invoke-gsc: #f keep-scm: #t optimize: #t output-file: output
         gsc-options: native-gsc-options]))
    (let* ((home (gerbil-home))
           (link-options (append
              (parameterize ((current-compile-gsc-options native-gsc-options))
                (gcc-ld-options))
              (call-with-input-file (path-expand "lib/libgerbil.ldd" home) read)))
           (modules
            (map (lambda (id)
                   (let* ((scm (find-static-module-file id))
                         (system? (and (installed-aot? id scm) #t)))
                     (let (module (hash ("module" id) ("scm" scm) ("system" system?)))
                       (unless (or (member id gerbil-runtime-modules)
                                   (hash-key? bootstrap (string->symbol id)))
                         (hash-put! module "deferred" #t))
                       module)))
                 ids)))
      (def templates
        (program-template-contexts (append contexts (map import-module runtime-imports))))
      (let* ((stub (path-expand program-stub-file output-dir))
               (base (delete-duplicates/hash
                       (append gerbil-runtime-modules
                         (map (cut hash-ref <> "module")
                           (filter (lambda (row) (not (hash-ref row "deferred" #f))) modules)))))
               (metadata (program-metadata-modules runtime-imports output-dir ids templates)))
          (set! modules (append modules metadata))
          (for-each (lambda (ctx)
                      (let (id (expander-context-id ctx))
                        (when id (hash-put! by-path (module-id->path-string id) ctx)))) templates)
          ;; gxc puts phase zero in the static unit. An installed SSI's
          ;; dynamic loader can still ask for that unit under its ~0 name.
          (def aliases
            (filter-map (lambda (row)
                          (def id (hash-ref row "module"))
                          (def scm (hash-ref row "scm"))
                          (and (not (string-index id #\~))
                               (> (file-info-size (file-info scm)) 0)
                               (cons (string-append id "~0") id)))
                        modules))
          (program-register-builtins! stub base
            (filter (cut hash-ref <> "deferred" #f) modules) by-path aliases))
      (call-with-output-file (path-expand program-manifest-file output-dir)
        (lambda (port)
          (write-json
           port
           (hash ("schema" program-schema)
                 ("modules" (list->vector modules))
                 ("stub" (path-expand program-stub-file output-dir))
                 ("library_dir" (path-expand "lib" home))
                 ("link_options" (list->vector link-options)))))))))


(def (yuanxu-clean-compiled-program output-dir)
  (def manifest (path-expand program-manifest-file output-dir))
  (def metadata (path-expand program-metadata-directory output-dir))
  (def (product-exists? path expected)
    (let (kind (module-source-type path))
      (when (and kind (not (eq? kind expected)))
        (error "unexpected selected program product type" path kind))
      kind))
  (def metadata? (product-exists? metadata 'directory))
  (def manifest? (product-exists? manifest 'regular))
  (def copies
    (if manifest?
      (let* ((plan (parameterize ((current-json-read-options
                                  (make-JSONReadOptions object-as-hash: #t)))
                     (call-with-input-file manifest read-json)))
             (stub (hash-ref plan "stub"))
             (rows (hash-ref plan "modules")))
        (unless (and (equal? (hash-ref plan "schema") program-schema)
                     (equal? (path-strip-directory stub) program-stub-file))
          (error "invalid selected program manifest" manifest))
        (def recorded-metadata
          (path-expand program-metadata-directory (path-directory stub)))
        ;; The link plan also references installed static inputs. Only copies
        ;; listed under this programme's own metadata directory are products.
        (filter-map (lambda (row)
                      (let* ((scm (hash-ref row "scm"))
                             (name (path-strip-directory scm)))
                        (and (equal? (path-strip-trailing-directory-separator
                                       (path-directory scm)) recorded-metadata)
                             (module-source-name? name)
                             (string-suffix? ".scm" name)
                             (path-expand name metadata))))
                    (if (vector? rows) (vector->list rows) rows)))
      '()))
  (def files
    (filter (cut product-exists? <> 'regular)
      (append (map (cut path-expand <> output-dir)
                   (list program-stub-file program-observation-file))
              (delete-duplicates/hash copies))))
  (def (remove-empty-directory directory)
    (when (and (product-exists? directory 'directory)
               (null? (directory-files (list path: directory ignore-hidden: 'dot-and-dot-dot))))
      (delete-directory directory)))
  (for-each delete-file files)
  (when metadata? (remove-empty-directory metadata))
  (when manifest? (delete-file manifest))
  (remove-empty-directory output-dir))


(def (program-register-builtins! stub modules metadata contexts aliases)
  (def eager-aliases
    (filter-map (lambda (alias) (and (member (cdr alias) modules) (car alias)))
                aliases))
  (let (forms (call-with-input-file stub
                 (lambda (port)
                   (read port)
                   (let loop ((forms []))
                     (let (form (read port))
                       (if (eof-object? form) (reverse forms)
                         (loop (cons form forms))))))))
    (call-with-output-file stub
      (lambda (port)
        (write `(define builtin-modules ',(append modules eager-aliases)) port)
        (newline port)
        ;; Compiler-owned dependency plans activate through Gerbil's existing
        ;; registry. Availability never implies eager initialization.
        (write (program-activation-form
          (map (lambda (module)
                 (let* ((id (hash-ref module "module"))
                        (scm (hash-ref module "scm"))
                        (context (or (hash-get contexts id)
                                     (and (not (string-index id #\~))
                                          (import-module (string->symbol (string-append ":" id)))))))
                   (list id
                     (and (> (file-info-size (file-info scm)) 0)
                       (string->symbol (path-strip-directory (path-strip-extension scm))))
                     scm
                     (if (module-context? context) (program-loader-imports context) '()))))
               metadata) aliases) port)
        (newline port)
        (for-each (lambda (form) (write form port) (newline port)) forms)))))

(def (program-observe-metadata imports output-dir)
  (if (null? imports) '()
    (let* ((observation (path-expand program-observation-file output-dir))
           (expression
             (call-with-output-string
               (lambda (port)
                 (write '(import :tao3k/yuanxu/module-system/building/program-metadata) port)
                 (newline port)
                 (write `(yuanxu-observe-program-metadata ,observation ',imports ',(load-path)) port))))
           (child (open-process
                    [path: (path-expand "bin/gxi" (gerbil-home))
                     arguments: ["-:debug=q" "-e" expression]
                     stdin-redirection: #f stdout-redirection: #f stderr-redirection: #f]))
           (status (process-status child)))
      (close-port child)
      (unless (= status 0) (error "compiler metadata observation failed" status))
      (call-with-input-file observation read))))

(def (program-metadata-modules imports output-dir builtin templates)
    ;; Additional library runtime dependencies are lazy too. In particular,
    ;; compiler/base constructs classes and cannot precede runtime/MOP setup.
    ;; Never merge these contexts into compile-exe's eager bootstrap order.
    (let ((rows (append (program-observe-metadata imports output-dir)
                  (filter-map
                    (lambda (ctx)
                      (let (id (symbol->string (expander-context-id ctx)))
                        (and (not (string-prefix? "gerbil/core" id))
                             (list id (find-static-module-file id)))))
                    (append
                      (apply append (map (lambda (ctx)
                                           (append (find-runtime-module-deps ctx) [ctx]))
                                         (map import-module imports)))
                      templates))))
          (seen (list->hash-table (map (lambda (id) (cons id #t))
                    (append builtin (map (cut string-append <> "~0") builtin)))))
          (directory (path-expand program-metadata-directory output-dir)))
      (create-directory* directory)
      (filter-map
        (lambda (row)
          (match row
            ([original source]
             (let* ((parent (and (string-suffix? "~0" original)
                                (substring original 0 (- (string-length original) 2))))
                    (static-parent (and parent
                                     (with-catch (lambda (_) #f)
                                       (lambda () (find-static-module-file parent)))))
                    (id (if (and static-parent (file-exists? static-parent)) parent original))
                    (static (or (and (equal? id parent) static-parent)
                                (with-catch (lambda (_) #f)
                                  (lambda () (find-static-module-file id))))))
               (and (not (hash-get seen id))
                 (let* ((installed? (and static (file-exists? static)))
                        (scm (if installed? static
                               (path-expand (string-append (static-module-name (string->symbol id)) ".scm")
                                            directory)))
                        (system? (and installed? (installed-aot? id scm))))
                   (unless installed?
                     (when (file-exists? scm) (delete-file scm))
                     (copy-file source scm))
                   (hash-put! seen id #t)
                   (hash-put! seen (string-append id "~0") #t)
                   (let (module (hash ("module" id) ("scm" scm)
                                       ("system" (and system? #t)) ("deferred" #t)))
                     ;; Lazy compiler metadata uses the archive's existing
                     ;; procedure layout. Installed objects keep their ABI.
                     (unless system?
                       (hash-put! module "host_layout" "separate-procedures"))
                     module)))))
            (else (error "invalid compiler metadata observation" row))))
        rows)))
