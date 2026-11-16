;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-source admission over the existing selection; Graph admission is lazy.
(import (runtime: :clan/poo/object)
        (only-in :std/list/list delete-duplicates/hash any)
        (only-in :tao3k/yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata)
        (only-in :tao3k/yuanxu/module-system/source/admission
                 module-source-type module-source-read module-source-name? module-source-admit-current!
                 call-with-module-source-read-cache))
(export module-test-projection module-test-file-source module-owner-test-projection
        admit-module-test-layout!)

;; Core owns the same directory calculation for projection and package layout
;; admission. The full audit is explicit so a narrow test demand stays narrow.
(def (qualification-location context owner metadata)
  (def init (and (.slot? context 'init-source) (.ref context 'init-source)))
  (def declared (assq 'test-dir metadata))
  (unless (and (string? init) declared (string? (cdr declared)))
    (error "qualification discovery requires an explicit :test-dir" init))
  (def mount (assq 'namespace-mount metadata))
  (def declaration (assq 'declaration-id metadata))
  (def parts
    (string-split
      (string-append (if (and mount (cdr mount))
                       (string-append (symbol->string (cdr mount)) "/") "")
                     (symbol->string (if declaration (cdr declaration) owner))) #\/))
  (unless (andmap module-source-name? parts)
    (error "invalid qualification owner identity" owner))
  (values (path-directory init) (string-split (cdr declared) #\/) parts))

;; Compare the complete Loader publication with the filesystem before handing
;; files to Gerbil. Independent suites and fixtures have separate entrypoints.
(def (admit-module-test-layout! context published
                                independent-directories: (independent '())
                                require-owner-tests?: (required? #f))
  (def roots (make-hash-table))
  (def directories (make-hash-table))
  (def owners (make-hash-table))
  (def (real-or-absent! path)
    (unless (memq (module-source-type path) '(#f directory))
      (error "qualification ancestor must be a real directory" path)))
  (def (descend base parts note!)
    (let loop ((parent base) (remaining parts))
      (if (null? remaining) parent
        (let (path (path-expand (car remaining) parent))
          (real-or-absent! path)
          (note! path)
          (loop path (cdr remaining))))))
  (def (test-tree base test-parts)
    (def root (descend base test-parts void))
    (def tree (path-expand "yanxu" root))
    (real-or-absent! tree)
    (hash-put! roots root tree)
    tree)
  ;; The declaration still owns a test tree when every Module is disabled
  ;; or an auto window is empty. Orphan suites must not disappear there.
  (def intent (.ref context 'intent))
  (def init (.ref context 'init-source))
  (for-each
    (lambda (window)
      (test-tree (path-directory init) (string-split (.ref window 'test-dir) #\/)))
    (if (.slot? intent 'windows) (.ref intent 'windows) (list intent)))
  (for-each
    (lambda (owner)
      (def metadata
        (yuanxu-module-source-ref-metadata ((.ref context 'locate) owner)))
      (let-values (((base test-parts owner-parts) (qualification-location context owner metadata)))
        (def tree (test-tree base test-parts))
        (def directory
          (descend tree owner-parts (lambda (path) (hash-put! directories path #t))))
        (when (hash-key? owners directory)
          (error "two Loader owners share a test directory" directory))
        (hash-put! owners directory owner)))
    (.ref context 'loader-roots))
  (def found '())
  (def (suite-name? name) (string-suffix? "-test.ss" name))
  (def (outside! path)
    (when (suite-name? path)
      (error "module test is outside the Loader test tree" path))
    (when (eq? (module-source-type path) 'directory)
      (for-each (lambda (name) (outside! (path-expand name path))) (directory-files path))))
  (def (scan! directory tree)
    (for-each
      (lambda (name)
        (def path (path-expand name directory))
        (case (module-source-type path)
          ((directory)
           (unless (hash-key? directories path)
             (error "no Loader owner for test directory" path))
           (scan! path tree))
          ((regular)
           (unless (and (equal? directory tree) (equal? name "interface.ss"))
             (unless (and (hash-key? owners directory) (suite-name? name))
               (error "test file is outside its Loader owner or has an invalid name" path))
             (set! found (cons path found))))
          (else (error "Loader test tree requires regular suites and real directories" path))))
      (test-directory-files directory)))
  (hash-for-each
    (lambda (root tree)
      (for-each
        (lambda (name)
          (unless (or (equal? name "yanxu") (member name independent))
            (outside! (path-expand name root))))
        (test-directory-files root))
      (scan! tree tree))
    roots)
  (when required?
    (let (populated (make-hash-table))
      (for-each
        (lambda (file)
          (hash-put! populated (path-strip-trailing-directory-separator (path-directory file)) #t))
        found)
      (hash-for-each
        (lambda (directory owner)
          (unless (hash-key? populated directory)
            (error "Loader owner has no published tests" owner directory)))
        owners)))
  (unless (equal? (list-sort string<? found) (list-sort string<? published))
    (error "Loader test publication does not match the test tree"
           (filter (lambda (file) (not (member file published))) found)
           (filter (lambda (file) (not (member file found))) published)))
  published)

;; Explicit runtime qualification files use the same observation authority as
;; module suites. Callers supply files, never a separately maintained guard.
(def (module-test-file-source files (inputs '()))
  (unless (and (list? files) (pair? files) (andmap string? files)
               (list? inputs) (andmap string? inputs))
    (error "explicit test source requires runtime file inputs" files))
  (def paths (map path-expand files))
  (def observations
    (map (lambda (path) (cons path (module-source-read path)))
      (delete-duplicates/hash (append paths (map path-expand inputs)))))
  (.o spec: paths
      admit-current: (lambda ()
                       (module-source-admit-current! observations "explicit test source changed"))))

(def (test-directory-files directory)
  (let (kind (module-source-type directory))
    (cond ((not kind) '())
          ((not (eq? kind 'directory)) (error "module tests must be a real directory" directory))
          (else (list-sort string<? (directory-files directory))))))

(def (module-owner-test-projection selection owner)
  (def context (.ref selection 'context))
  (when (memq owner (.ref context 'denied-modules))
    (error "test owner is disabled" owner))
  (scan-module-test-sources selection context (list owner) #f))

(def (module-test-projection selection (owners #f) (suite #f))
  (unless (memq suite '(#f integration qualification)) (error "unknown module test suite" suite))
  (def context (.ref selection 'context))
  (when (and owners (.slot? context 'resolve-root) (list? owners) (andmap symbol? owners))
    (set! owners (map (.ref context 'resolve-root) owners)))
  ;; Explicit test demands stay bounded. Aggregate discovery includes the
  ;; auto catalog; profile defaults use the product's dependency closure.
  (def order (.ref context 'selected))
  (def (eligible? owner)
    (and (not (memq owner (.ref context 'denied-modules)))
         (or (memq owner order)
             (and (.slot? context 'eligible?) ((.ref context 'eligible?) owner)))))
  (unless (or (not owners)
              (and (list? owners) (andmap symbol? owners)
                   (= (length owners) (length (delete-duplicates/hash owners from-end?: #t)))
                   (andmap eligible? owners)))
    (error "test owners must be distinct eligible members of the selection" owners order))
  ;; A category selects a dependency-closed product, shared with native Make.
  ;; Ordinary explicit test discovery remains narrow (and Graph-lazy); an
  ;; explicitly requested owner list remains bounded by the eligibility check.
  (def selected-owners
    (cond (owners owners)
          ((and (.slot? context 'intent)
                (let (intent (.ref context 'intent))
                  (any (lambda (window) (and (.slot? window 'profile) (.ref window 'profile)))
                       (if (.slot? intent 'windows) (.ref intent 'windows) (list intent)))))
           (.ref (.ref selection 'selected-graph) 'module-order))
          ((.slot? context 'loader-roots) (.ref context 'loader-roots))
          (else order)))
  (if (and (not suite) (.slot? selection '.module-test-source))
    (let* ((sources (map (.ref selection '.module-test-source) selected-owners))
           (admit-current (lambda ()
                       ((.ref selection 'admit-current))
                       (for-each (lambda (source) ((.ref source 'admit-current))) sources))))
      (.o selected-graph: (.ref selection 'selected-graph)
          spec: (foldr append '() (map (cut .ref <> 'spec) sources))
          admit-current))
    (scan-module-test-sources selection context selected-owners suite)))

(def (scan-module-test-sources selection context selected-owners suite)
  ;; Module-owned tests retain the publication's private inputs. Qualification
  ;; files belong to the init declaration and use only the Loader's owner
  ;; metadata here. Their build projection admits the selected Graph separately.
  (unless (eq? suite 'qualification)
    (for-each (lambda (owner) ((.ref selection 'prepare-publication) owner)) selected-owners))
  (def observations '())
  (def directories '())
  (def parents '())
  (def paths '())
  (def (observe-parent! directory)
    (let (kind (module-source-type directory))
      (unless (memq kind '(#f directory))
        (error "qualification ancestor must be a real directory" directory))
      (set! parents (cons (cons directory kind) parents))))
  ;; Qualification belongs to the init owner, never to a module implementation.
  ;; Observe ancestor kinds without enumerating sibling owners or Core suites.
  (def (qualification-directory owner metadata)
    (let-values (((base test-parts owner-parts) (qualification-location context owner metadata)))
      (let walk ((parent base) (parts (append test-parts '("yanxu") owner-parts)))
        (let (child (path-expand (car parts) parent))
          (if (null? (cdr parts)) child
            (begin (observe-parent! child) (walk child (cdr parts))))))))
  (def (observe-directory! directory)
    (def kind (module-source-type directory))
    (def names (test-directory-files directory))
    (set! directories (cons (list directory kind names) directories))
    names)
  (for-each
   (lambda (owner)
     (let* ((source ((.ref context 'locate) owner))
            (metadata (yuanxu-module-source-ref-metadata source))
            (root (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
       (unless root (error "module tests require an admitted local module root" owner))
       (let* ((base (if (eq? suite 'qualification)
                      (qualification-directory owner metadata)
                      (path-expand "tests" (cdr root))))
              (directory (if (eq? suite 'integration) (path-expand "integration" base) base))
              (_parent (when (eq? suite 'integration) (observe-directory! base)))
              (names (observe-directory! directory)))
         (for-each
          (lambda (name)
            (when (string-suffix? ".ss" name)
              (let (file (path-expand name directory))
                ;; Helpers are observed, but only *-test.ss are harness inputs.
                (set! observations (cons (cons file (module-source-read file)) observations))
                (when (string-suffix? "-test.ss" name)
                  (set! paths (cons file paths)))))) names)))) selected-owners)
  (def (sources-current!)
    (for-each
      (lambda (row)
        (unless (eq? (module-source-type (car row)) (cdr row))
          (error "qualification ancestor changed; use a fresh init context" (car row)))) parents)
    (for-each
     (lambda (row)
       (unless (and (eq? (module-source-type (car row)) (cadr row))
                    (equal? (test-directory-files (car row)) (caddr row)))
         (error "module test directory changed; use a fresh init context" (car row)))) directories)
    (module-source-admit-current! observations "module test source changed; use a fresh init context"))
  (def (current!)
    ;; Source admission retains the reader's demanded dependency observations.
    ;; It must not acquire the complete configuration Graph as a side effect.
    ;; A realized/foreign selection may run package effects: keep that call
    ;; outside the pure window and start fresh afterwards.
    (if (and (.slot? selection 'package-current) (not (.ref selection 'package-current)))
      (call-with-module-source-read-cache
        (lambda () ((.ref selection 'admit-current)) (sources-current!)))
      (begin
        ((.ref selection 'admit-current))
        (call-with-module-source-read-cache sources-current!))))
  (current!)
  (.o selected-graph: (.ref selection 'selected-graph)
      spec: (reverse paths) admit-current: current!))
