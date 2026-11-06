;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(import (only-in :gerbil/expander core-import-module core-bind-root-syntax!
                 expander-context-id core-resolve-library-module-path
                 core-bound-module-prelude? syntax-local-e module-context?
                 module-source-path prelude-context-path core-read-module/sexp
                 core-library-package-plist core-library-package-path-prefix)
        (only-in :std/list/list delete-duplicates/hash))
(export package-prelude-identity register-module-build-source! register-yuanxu-build-source! module-build-source-path
        call-with-build-input-path)

;; The init-owned source projection chooses its compiler inputs. std/make owns
;; the output directory separately; runtime consumers retain their normal path.
;; This is a native Gerbil dynamic extent, not another resolver or module cache.
(def (call-with-build-input-path output action
                                 (refuse (lambda () (error "source projection changed its compiler input context")))
                                 source-roots: (source-roots '())
                                 make-source: (make-source #f))
  (def previous (load-path))
  (def (canonical path)
    (path-strip-trailing-directory-separator (path-normalize (path-expand path))))
  (def destination (canonical output))
  (def (output? path) (string=? destination (canonical path)))
  (def inputs (append (filter (lambda (path) (not (output? path))) previous)
                     (filter output? previous)))
  (unless (ormap output? inputs)
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

(def (register-module-build-source! root expected-package prelude: (expected-prelude #f))
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
  (add-load-path! directory))

;; The package owns this source declaration. Consumers never reconstruct it
;; from the public language name or from a compiled artifact's filename.
(def yuanxu-language-file "prelude.ss")

(def (resolve-build-library library directory)
  (let (previous (load-path))
    (dynamic-wind
      (lambda () (set-load-path! (list directory)))
      (lambda ()
        (with-catch
          (lambda (exception)
            (if (syntax-error? exception) #f (raise exception)))
          (lambda () (core-resolve-library-module-path library))))
      (lambda () (set-load-path! previous)))))

(def (module-build-source-path context package-root)
  ;; Package/build internals own source resolution, never configuration users
  ;; or dependency traversal. Consume runtime bindings and package resolution;
  ;; a public language name does not prescribe its source filename.
  (def identity (expander-context-id context))
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
          (and (eq? (pgetq package: properties) 'yuanxu)
               (eq? (pgetq prelude: properties) library)))
        (path-expand yuanxu-language-file package-root))
       (else
        ;; Resolve within the declared package even when the runtime context
        ;; came from the output library. Foreign prefixes have no candidate.
        (let (prefix (core-library-package-path-prefix package-root))
          (and (or (not prefix) (string-prefix? prefix (symbol->string identity)))
               (resolve-build-library library package-root)))))))
  (and (owned-source? source)
    (let-values (((_prelude actual _namespace _body) (core-read-module/sexp source)))
      (unless (eq? identity actual)
        (error "compiler source identity mismatch" identity actual source))
      source)))

(def (register-yuanxu-build-source! root)
  (def library (package-source-path root 'yuanxu))
  (def language ':tao3k/yuanxu/prelude)
  (def source (path-expand yuanxu-language-file library))
  (def output (path-expand "lib" (gerbil-path)))
  ;; Gerbil resolves the language in Make's output library. On a clean checkout
  ;; the package prefix cannot resolve the off-prefix source language by ID.
  ;; The bootstrap has one local macro prerequisite. Apply Gerbil's timestamp
  ;; rule before using either generated interface during entry expansion.
  (def installed (resolve-build-library language output))
  (def selected
    (or (and installed
             (not (file-newer? source installed))
             (not (file-newer? (path-expand "gerbil.pkg" library) installed))
             (let (syntax-interface
                    (resolve-build-library ':yuanxu/module-system/selection/init-syntax output))
               (and syntax-interface
                    (not (file-newer?
                           (path-expand "module-system/selection/init-syntax.ss" library)
                           syntax-interface))))
             installed)
        source))
  (def prelude (core-import-module selected))
  (unless (eq? (expander-context-id prelude) 'tao3k/yuanxu/prelude)
    (error "build prelude identity mismatch" (expander-context-id prelude)))
  (add-load-path! library)
  (core-bind-root-syntax! language prelude #t))
