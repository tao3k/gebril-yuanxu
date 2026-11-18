;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(import (only-in :gerbil/expander core-import-module core-bind-root-syntax!
                 expander-context-id core-resolve-library-module-path syntax-e
                 core-bound-module-prelude? syntax-local-e module-context?
                 module-source-path prelude-context-path core-read-module/sexp
                 core-library-package-plist)
        (only-in :std/list/list delete-duplicates/hash filter-map find)
        (only-in :tao3k/yuanxu/module-system/source/module-binding module-binding-action))
(export package-library-prefix package-prelude-identity register-module-build-source! module-build-source-path module-build-library-source-path module-build-import-identity module-build-resolve-library
        call-with-build-input-path call-with-build-source-fallbacks package-build-script-path
        package-module-source-path)

;; The init-owned source projection chooses its compiler inputs. std/make owns
;; the output directory separately; runtime consumers retain their normal path.
;; This is a native Gerbil dynamic extent, not another resolver or module cache.
(def (call-with-build-input-path output action
                                 (refuse (lambda () (error "source projection changed its compiler input context")))
                                 source-roots: (source-roots '())
                                 make-source: (make-source #f))
  (with-build-input-path output action refuse source-roots '() make-source))

(def (call-with-build-source-fallbacks roots action)
  (with-build-input-path #f action
    (lambda () (error "source projection changed its compiler input context"))
    '() roots #f))

(def (with-build-input-path output action refuse source-roots source-fallbacks make-source)
  (def previous (load-path))
  (def (canonical path)
    (path-strip-trailing-directory-separator (path-normalize (path-expand path))))
  ;; A projection can guard the native runtime order without adding a
  ;; compiler output directory. Only Make dispatch needs that fallback.
  (def destination (and output (canonical output)))
  (def (output? path) (and destination (string=? destination (canonical path))))
  (def inputs (append (filter (lambda (path) (not (output? path))) previous)
                     (filter output? previous)))
  (when (and destination (not (ormap output? inputs)))
    (set! inputs (append inputs (list output))))
  ;; A declared checkout owns its compiler sources even when an ordinary
  ;; prerequisite contains compiled copies. Gerbil still resolves identities
  ;; and paths. Keep the caller's prerequisite order and output fallback.
  (unless (null? source-roots)
    (let* ((sources (filter (lambda (path) (not (output? path)))
                            (delete-duplicates/hash source-roots key: canonical from-end?: #t)))
           (source-origins (map canonical sources)))
      (set! inputs (append sources (filter (lambda (path)
                                            (not (member (canonical path) source-origins)))
                                          inputs)))))
  (unless (null? source-fallbacks)
    ;; The same prerequisite may appear in GERBIL_LOADPATH and Gerbil's
    ;; default user library. Keep its first position when adding fallbacks.
    (set! inputs (delete-duplicates/hash (append inputs source-fallbacks)
                   key: canonical from-end?: #t)))
  (def input-origins (map canonical inputs))
  (dynamic-wind
    (lambda () (set-load-path! inputs))
    action
    (lambda ()
      (def actual (map canonical (load-path)))
      ;; Gerbil make prepends srcdir once. Accept only that native transition
      ;; during dispatch and restore it before returning to source guards.
      (def unchanged?
        (or (equal? input-origins actual)
            (and make-source (equal? (cons (canonical make-source) input-origins) actual))))
      (set-load-path! previous)
      ;; An author failure cannot hide an input mutation and leave a prepared
      ;; result reusable. Restore first, then refuse on every kind of exit.
      (unless unchanged? (refuse)))))

;; Gerbil accepts string and symbol package names in source headers. The
;; installed path-prefix helper assumes a symbol even on unchecked builds.
(def (package-library-prefix directory)
  (let (name (pgetq package: (core-library-package-plist directory)))
    (cond
     ((not name) #f)
     ((symbol? name) (string-append (symbol->string name) "/"))
     ((string? name) (string-append name "/"))
     (else (error "invalid Gerbil package name" directory name)))))

(def (package-prelude-identity root)
  ;; Gerbil owns package/header resolution. Only the root's actual prelude file
  ;; may publish an identity outside its library prefix, matching gerbil.pkg.
  (def file (path-expand "prelude.ss" root))
  (def selected (memq 'prelude: (core-library-package-plist root #t)))
  (and selected (pair? (cdr selected)) (file-exists? file)
    (let-values (((base identity namespace body) (core-read-module/sexp file)))
      (and (eq? (cadr selected)
                (string->symbol (string-append ":" (symbol->string identity))))
           identity))))

(def (package-source-path root expected-package)
  (let* ((directory (path-normalize root))
         (metadata (path-expand "gerbil.pkg" directory))
         (properties (core-library-package-plist directory #t))
         (package (and (list? properties) (memq 'package: properties))))
    (unless (and package (pair? (cdr package))
                 (eq? (cadr package) expected-package))
      (error "build source package identity mismatch" metadata expected-package))
    directory))

(def (package-build-script-path root)
  ;; Match Gerbil gxpkg's build: property and standard build.ss default.
  (def properties (core-library-package-plist root #t))
  (path-expand (or (and (list? properties) (pgetq build: properties)) "build.ss") root))

(def (register-module-build-source! root expected-package prelude: (expected-prelude #f)
                                      add-load-path?: (add-path? #t))
  (def directory (package-source-path root expected-package))
  (def identity (package-prelude-identity directory))
  ;; Verify before changing the expander or its search path. An off-prefix
  ;; language is owned by the package's source header and gerbil.pkg together.
  (when (and expected-prelude (not (eq? expected-prelude identity)))
    (error "build source prelude identity mismatch" directory expected-prelude identity))
  (when identity
    (let (context (core-import-module (path-expand "prelude.ss" directory)))
      (core-bind-root-syntax!
        (string->symbol (string-append ":" (symbol->string identity))) context #t)))
  (when add-path? (add-load-path! directory)))

;; The package owns this source declaration. Consumers never reconstruct it
;; from the public language name or from a compiled artifact's filename.
(def yuanxu-language-file "prelude.ss")

;; This projects a candidate within one declared source owner. Gerbil's
;; symbolic resolver still owns runtime selection and the header below must
;; confirm the candidate's identity. Do not replace the process-wide search
;; path: parallel Make workers use it while expanding their own imports.
(def (owned-build-library-path identity directory)
  (def name (symbol->string identity))
  (def prefix (package-library-prefix directory))
  (and (or (not prefix) (string-prefix? prefix name))
    (let ()
      (def relative
        (if prefix (substring name (string-length prefix) (string-length name)) name))
      (def path (path-expand relative directory))
      (def extension (path-extension path))
      (def base (path-strip-extension path))
      (find file-exists?
        (cons (string-append base ".ssi")
              (if (string-empty? extension)
                (map (cut string-append path <>) '(".ss" ".sld" ".scm"))
                (list path)))))))

;; A symbolic dependency request resolves exactly once through Gerbil. Check
;; the resolved SSI header in that same observation; re-resolving a path just
;; returned by the compiler can observe another Make worker's input window.
(def (module-build-resolve-library identity)
  (def library (string->symbol (string-append ":" (symbol->string identity))))
  (def path (core-resolve-library-module-path library))
  (when (equal? (path-extension path) ".ssi")
    (let-values (((_prelude actual _namespace _body) (core-read-module/sexp path)))
      (unless (eq? identity actual)
        (error "compiled import identity differs from requested library" path identity actual))))
  path)

;; Gerbil can resolve a symbolic import to an SSI path before invoking the
;; import hook. Read its inert header, not the initializer, and authenticate
;; that header against the runtime's own library resolver before source lookup.
(def (module-build-import-identity path)
  (def request (syntax-e path))
  (cond
   ((symbol? request)
    (let (text (symbol->string request))
      (and (> (string-length text) 1) (char=? (string-ref text 0) #\:)
           (string->symbol (substring text 1 (string-length text))))))
   ((and (string? request) (string=? (path-extension request) ".ssi"))
    (let-values (((_prelude identity _namespace _body) (core-read-module/sexp request)))
      (def library (string->symbol (string-append ":" (symbol->string identity))))
      (unless (equal? (path-normalize (path-expand request))
                      (path-normalize (path-expand (core-resolve-library-module-path library))))
        (error "compiled import identity differs from runtime package resolution" request identity))
      identity))
   (else #f)))

(def (module-build-source-path context package-root)
  (module-build-library-source-path (expander-context-id context) package-root))

(def (module-build-library-source-path identity package-root)
  ;; Package/build internals own source resolution, never configuration users
  ;; or dependency traversal. Consume runtime bindings and package resolution;
  ;; a public language name does not prescribe its source filename.
  (def library (and (symbol? identity)
                   (string->symbol (string-append ":" (symbol->string identity)))))
  (def root (string-append (path-strip-trailing-directory-separator (path-normalize package-root)) "/"))
  (def (owned-source? path)
    (and (string? path) (string-prefix? root (path-normalize path))
         (member (path-extension path) '(".ss" ".scm" ".sld"))))
  (def bound-source
    (and library (core-bound-module-prelude? library)
      (let (bound (syntax-local-e library))
        (if (module-context? bound) (module-source-path bound) (prelude-context-path bound)))))
  (def source
    (and library
      (cond
       ((owned-source? bound-source) bound-source)
       ((let (properties (core-library-package-plist package-root))
          (and (eq? (pgetq package: properties) 'tao3k/yuanxu)
               (eq? (pgetq prelude: properties) library)))
        (path-expand yuanxu-language-file package-root))
       (else
        ;; Resolve within the declared package even when the runtime context
        ;; came from the output library. Foreign prefixes have no candidate.
        (owned-build-library-path identity package-root)))))
  (and (owned-source? source)
    (let-values (((_prelude actual _namespace _body) (core-read-module/sexp source)))
      (unless (eq? identity actual)
        (error "compiler source identity mismatch" identity actual source))
      source)))

;; Package tools are only needed when a window refers to an installed source.
(def package-store-root
  (module-binding-action "gerbil/tools/gxpkg" 'pkg-root-dir))
(def installed-packages
  (module-binding-action "gerbil/tools/gxpkg" 'pkg-list))

;; Gerbil's package roster is authoritative for an exported ModuleSource.
;; Look up its source header without importing any provider code.
(def (package-module-source-path library)
  (def text (symbol->string library))
  (def identity (string->symbol (substring text 1 (string-length text))))
  (def name (symbol->string identity))
  (def store (package-store-root '()))
  (def matches
    (filter-map
      (lambda (package)
        (def root (path-expand package store))
        (def prefix (package-library-prefix root))
        (and prefix (string-prefix? prefix name)
             (let (source (path-expand
                            (string-append (substring name (string-length prefix) (string-length name)) ".ss")
                            root))
               (and (file-exists? source)
                    (let-values (((_prelude declared _namespace _body) (core-read-module/sexp source)))
                      (and (eq? identity declared) (path-normalize source)))))))
      (installed-packages '())))
  (match matches
    ([source] source)
    ([] (error "ModuleSource owner is absent from installed Gerbil packages" library))
    (else (error "ModuleSource owner is ambiguous in installed Gerbil packages" library matches))))
