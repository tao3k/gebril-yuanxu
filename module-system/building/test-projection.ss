;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Inert native std/test file selection over the existing selected Graph.
(import (only-in :clan/poo/object .o .ref .slot?)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :core/module-system/source/objects poo-flow-module-source-ref-metadata)
        (only-in :core/module-system/source/admission
                 module-source-type module-source-read module-source-admit-current!
                 call-with-module-source-read-cache))
(export module-test-projection module-test-file-source module-test-execution)

;; Native Gerbil import in a private context, demanded only by explicit .run.
;; This is the existing Ops prototype factory, not a module/runtime Loader.
(def testing-executor
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :core/observability/testing-script))
      (eval-syntax 'testing-script-for-source))))
(def (module-test-execution source)
  ((force testing-executor) source))

;; Explicit native qualification files use the same observation authority as
;; module suites. Callers supply files, never a separately maintained guard.
(def (module-test-file-source files)
  (unless (and (list? files) (pair? files) (andmap string? files))
    (error "explicit test source requires native file inputs" files))
  (def paths (map path-expand files))
  (def inputs (map (lambda (path) (cons path (module-source-read path))) paths))
  (.o spec: paths
      admit-current: (lambda ()
                       (module-source-admit-current! inputs "explicit test source changed"))))

(def (test-directory-files directory)
  (let (kind (module-source-type directory))
    (cond ((not kind) '())
          ((not (eq? kind 'directory)) (error "module tests must be a real directory" directory))
          (else (list-sort string<? (directory-files directory))))))

(def (module-test-projection selection (owners #f) (suite #f))
  (unless (memq suite '(#f integration)) (error "unknown module test suite" suite))
  (def graph (.ref selection 'selected-graph))
  (def order (.ref graph 'module-order))
  (unless (or (not owners)
              (and (list? owners) (andmap symbol? owners)
                   (= (length owners) (length (delete-duplicates/hash owners from-end?: #t)))
                   (andmap (cut memq <> order) owners)))
    (error "test owners must be distinct members of the selected Graph" owners order))
  (def observations '())
  (def directories '())
  (def paths '())
  (def (observe-directory! directory)
    (def kind (module-source-type directory))
    (def names (test-directory-files directory))
    (set! directories (cons (list directory kind names) directories))
    names)
  (for-each
   (lambda (owner)
     (when (or (not owners) (memq owner owners))
       (let* ((source ((.ref (.ref selection 'context) 'locate) owner))
              (metadata (poo-flow-module-source-ref-metadata source))
              (root (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
         (unless root (error "module tests require an admitted local module root" owner))
         (let* ((base (path-expand "tests" (cdr root)))
                (directory (if suite (path-expand (symbol->string suite) base) base))
                (_parent (when suite (observe-directory! base)))
                (names (observe-directory! directory)))
           (for-each
            (lambda (name)
              (when (string-suffix? ".ss" name)
                (let (file (path-expand name directory))
                  ;; Helpers are observed, but only *-test.ss are harness inputs.
                  (set! observations (cons (cons file (module-source-read file)) observations))
                  (when (string-suffix? "-test.ss" name)
                    (set! paths (cons file paths)))))) names))))) order)
  (def (sources-current!)
    ((.ref graph 'admit-current))
    (for-each
     (lambda (row)
       (unless (and (eq? (module-source-type (car row)) (cadr row))
                    (equal? (test-directory-files (car row)) (caddr row)))
         (error "module test directory changed; use a fresh init context" (car row)))) directories)
    (module-source-admit-current! observations "module test source changed; use a fresh init context"))
  (def (current!)
    ;; An unrealized Module selection's admission is source-only. Its selected
    ;; Graph delegates to the same guard; share observations, not acceptance.
    ;; A realized/foreign selection may run package effects: keep that call
    ;; outside the pure window and start fresh afterwards.
    (if (and (.slot? selection 'package-current) (not (.ref selection 'package-current)))
      (call-with-module-source-read-cache
        (lambda () ((.ref selection 'admit-current)) (sources-current!)))
      (begin
        ((.ref selection 'admit-current))
        (call-with-module-source-read-cache sources-current!))))
  (current!)
  (.o selected-graph: graph spec: (reverse paths) admit-current: current!))
