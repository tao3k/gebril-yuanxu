;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Project selected sources to ordinary std/build-script specifications.
;;; std/make owns compilation, dependency scheduling and clean.
(import (only-in "./native-products.ss" native-target-kind native-target-spec native-program-targets)
        (only-in :std/string/path path-absolute?)
        (only-in "./artifacts.ss" call-with-build-artifact-issuance run-build-artifact-process
                 require-build-artifacts! current-build-output-directory test-build-publication)
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :clan/poo/object .o .ref .get .call)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/source/build unique-build-inputs module-test-source-spec retained-build-entries)
        (only-in :yuanxu/module-system/source/preparation build-target-name yuanxu-prepare-module-retained-source yuanxu-prepare-module-build-source call-with-module-compiler-inputs)
        (only-in :yuanxu/module-system/source/admission module-source-type
                 module-source-name? module-source-admit-current! call-with-module-source-read-cache))
(import (only-in :yuanxu/module-system/building/source-package package-prelude-identity))
(export yuanxu-project-source-spec)
(def (project-std-make-specs entries package-prefix language)
  ;; std/make names products using prefix + target, while gxc uses the
  ;; declared module identity. Keep those names identical for every target.
  (def groups (make-hash-table))
  (def order '())
  (for-each
    (lambda (entry)
      (def id (.get entry compiler-identity))
      (def name (build-target-name id package-prefix language))
      (def full (symbol->string id))
      (def prefix
        (if (equal? full (if (string-empty? package-prefix) name
                            (string-append package-prefix "/" name)))
          #f
          (substring full 0 (- (string-length full) (string-length name) 1))))
      (unless (hash-key? groups prefix)
        (hash-put! groups prefix '())
        (set! order (cons prefix order)))
      (hash-update! groups prefix
        (cut cons (native-target-spec entry name) <>) '())) entries)
  ;; The admitted cross-package prelude bootstraps independently of Core.
  (map (lambda (native-prefix)
         (.o prefix: native-prefix spec: (reverse (hash-ref groups native-prefix))))
       (append (filter identity (reverse order))
               (if (hash-key? groups #f) '(#f) '()))))
(def (merge-build-entries selected kept)
  (let ((seen (make-hash-table-eq)) (result '()))
    (for-each
     (lambda (entry)
       (let (id (.ref entry 'compiler-identity))
         (if (hash-key? seen id)
           (let (old (hash-ref seen id))
             (unless (and (equal? (.ref old 'path) (.ref entry 'path))
                          (equal? (.ref old 'options) (.ref entry 'options))
                          (eq? (native-target-kind old) (native-target-kind entry))
                          (equal? (.ref (.ref old 'input) 'compiler-forms)
                                  (.ref (.ref entry 'input) 'compiler-forms)))
               (error "conflicting compiler inputs" id)))
           (begin (hash-put! seen id entry) (set! result (cons entry result))))))
     (append selected kept))
    (reverse result)))

(def (yuanxu-project-source-spec source retained root entry-source demand: (demand #f))
  (if demand
    (module-test-source-spec source demand root entry-source retained)
    (project-selected-source-spec source retained root entry-source)))

(def (project-selected-source-spec source retained root entry-source)
  ;; Executable issuance belongs to an explicit native test demand. Module
  ;; Build roots retain their existing library-only public contract.
  (when (ormap (lambda (spec) (and (pair? spec) (eq? (car spec) exe:))) retained)
    (error "native programs require an explicit init-owned test demand"))
  (when (current-module-build-phase?)
    (error "Module build phase cannot recursively project the root specification"))
  (unless (and (string? root) (path-absolute? root)
               (string? entry-source) (path-absolute? entry-source))
    (error "build projection requires absolute source and entry roots"))
  (def entry-input (yuanxu-prepare-module-build-source entry-source void))
  (def package-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref entry-input 'compiler-identity)))))
  ;; Like package-prefix, this is one observed input of this projection. The
  ;; complete source/package guards below still bracket native compilation.
  (def language (package-prelude-identity root))
  (let* ((view (if (string? source) (yuanxu-load-modules source) source))
         (graph (.ref view 'build-graph))
         ;; Preparing retained headers only observes source and package metadata.
         ;; Share the existing pure read window across their own source guards.
         ;; The projection owns selected-Graph admission once per boundary; end
         ;; this window before compilation or independent currentness checks.
         (kept (call-with-module-source-read-cache
                 (lambda ()
                   (retained-build-entries retained root package-prefix (.ref graph 'entries)))))
         ;; A selection may use Modules from another source package. Observe
         ;; their inputs and Graph guards below, but let that package's native
         ;; build own its output names and compiler options.
         (all-entries (merge-build-entries (.ref graph 'entries) kept))
         (entries
           (filter (lambda (entry)
                     (let (identity (.ref entry 'compiler-identity))
                       (or (eq? identity language)
                           (string-prefix? (string-append package-prefix "/")
                             (symbol->string identity))))) all-entries))
         (foreign? (not (= (length entries) (length all-entries))))
         (observed (unique-build-inputs
                     (append (.ref entry-input 'source-inputs) (.ref graph 'compiler-inputs)
                       (foldr append '()
                         (map (lambda (entry) (.ref (.ref entry 'input) 'source-inputs)) kept)))))
         (build-value
          (map (lambda (entry)
                 (let* ((name (build-target-name (.ref entry 'compiler-identity) package-prefix language))
                        (expected (path-expand (string-append name ".ss") root)))
                   (unless (equal? (path-normalize expected) (path-normalize (.ref entry 'path)))
                     (error "source target does not match repository path" name (.ref entry 'path)))
                   (native-target-spec entry name))) entries)))
    (unless (null? (.ref graph 'other-projections))
      (error "direct source projection requires a dedicated consumer for generated contributions"))
    (def (current!)
      (call-with-module-source-read-cache
        (lambda ()
          ((.ref graph 'compiler-current))
          (for-each (lambda (entry) ((.ref (.ref entry 'input) 'admit-current))) kept)
          (module-source-admit-current! observed))))
    (def (publication-current!)
      (current!)
      ;; Output issuance covers the entire selected Graph. A package-only
      ;; compilation cannot certify outputs owned by its source dependencies.
      (when foreign?
        (error "selected Graph publication requires all package owners")))
    (current!)
    (.o (:: projection) selected-graph: (.ref graph 'selected-graph) build-graph: graph
        std-make-specs: (project-std-make-specs entries package-prefix language)
        compiler-identities: (map (cut .ref <> 'compiler-identity) entries)
        program-targets: (native-program-targets entries)
        source-inputs: observed
        ;; Ordinary package Make and issued compilation share role lowering,
        ;; not authority. A package build does not mint publication approval.
        .with-compiler-inputs:
        (lambda (action)
          (current!)
          (begin0 (call-with-module-compiler-inputs entries action) (current!)))
        .compile: (lambda (libdir action)
                    (publication-current!)
                    (call-with-build-artifact-issuance projection libdir
                      (lambda () (.call projection .with-compiler-inputs action))))
        .process: (lambda (libdir command)
                   (publication-current!)
                   (run-build-artifact-process projection libdir command))
        source-root: root spec: build-value admit-current: current!)))
