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
(export module-test-projection module-test-file-source module-owner-test-projection)

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
  ;; Ordinary test discovery follows init roots without composing a Graph.
  ;; Profile defaults below instead use the product's shared dependency closure.
  ;; Auto leaves may make bounded explicit demands through the same policy.
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
  (def profiled?
    (and (.slot? context 'intent)
         (let (intent (.ref context 'intent))
           (any (lambda (window) (and (.slot? window 'profile) (.ref window 'profile)))
                (if (.slot? intent 'windows) (.ref intent 'windows) (list intent))))))
  ;; A category selects a dependency-closed product, shared with native Make.
  ;; Ordinary explicit test discovery remains narrow (and Graph-lazy); an
  ;; explicitly requested owner list remains bounded by the eligibility check.
  (def selected-owners
    (cond (owners owners)
          (profiled? (.ref (.ref selection 'selected-graph) 'module-order))
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
  ;; Reuse the selection's publication/source cache, including the reader's
  ;; Gerbil-observed private and compiler dependencies. Do not resolve a second
  ;; Graph or link a business scope. A test owner still needs valid sources;
  ;; dependency/feature composition is admitted only on explicit Graph demand.
  (for-each (lambda (owner) ((.ref selection 'prepare-publication) owner)) selected-owners)
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
  (def qualification-root
    (and (eq? suite 'qualification)
         (let (init (and (.slot? context 'init-source) (.ref context 'init-source)))
           (unless (string? init) (error "qualification discovery requires an init source"))
           (def intent (and (.slot? context 'intent) (.ref context 'intent)))
           (def directory (if (and intent (.slot? intent 'test-dir)) (.ref intent 'test-dir) "t"))
           (let walk ((parent (path-directory init)) (parts (string-split directory #\/)))
             (let (child (path-expand (car parts) parent))
               (observe-parent! child)
               (if (null? (cdr parts)) child (walk child (cdr parts))))))))
  (def (observe-directory! directory)
    (def kind (module-source-type directory))
    (def names (test-directory-files directory))
    (set! directories (cons (list directory kind names) directories))
    names)
  (for-each
   (lambda (owner)
     (let* ((source ((.ref context 'locate) owner))
            (metadata (yuanxu-module-source-ref-metadata source))
            (mount (assq 'namespace-mount metadata))
            (declaration (assq 'declaration-id metadata))
            (qualification-name
              (string-append
                (if (and mount (cdr mount))
                  (string-append (symbol->string (cdr mount)) "/") "")
                (symbol->string (if declaration (cdr declaration) owner))))
            (root (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
       (unless root (error "module tests require an admitted local module root" owner))
       (when qualification-root
         (let (parts (string-split qualification-name #\/))
           (unless (andmap module-source-name? parts)
             (error "invalid qualification owner identity" owner))
           (let loop ((directory qualification-root) (remaining parts))
             (when (pair? (cdr remaining))
               (let (parent (path-expand (car remaining) directory))
                 (observe-parent! parent)
                 (loop parent (cdr remaining)))))))
       (let* ((base (if qualification-root
                     (path-expand qualification-name qualification-root)
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
