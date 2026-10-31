;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Catalog scale, declaration demand and resolver scale are separate controls.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :yuanxu/module-system/interface yuanxu-load-modules)
        (only-in :yuanxu/module-system/building/test-projection module-test-projection)
        (only-in :yuanxu/module-system/source/selection select-module-graph)
        (only-in :yuanxu/module-system/graph/funs module-closure)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-observe)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture))
(export module-loading-scale-test)
(.def Workspace
  .acquire: (lambda ()
              (let (root (path-normalize (make-temporary-file-name "module-scale-")))
                (create-directory root) root))
  .release: clear-temporary-file!)
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def module-loading-scale-test
  (test-suite "One Graph at thousand and ten-thousand module scale"
    (yuanxu-test-fixture "catalog growth does not evaluate or read unselected module bodies"
      (root Workspace)
      (write-source (path-expand "gerbil.pkg" root)
        (string-append "(package: " (symbol->string (gensym 'scale-)) ")"))
      (write-source (path-expand "init.ss" root)
        "(yuanxu! source: \"./modules\" mode: auto)")
      (def chosen (path-expand "modules/chosen/" root))
      (write-source (path-expand "types.ss" chosen)
        "(import (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract) (only-in :clan/poo/object object?)) (def ScopeContract (yuanxu-predicate-contract 'scale object? (lambda (_v _c) '()))) (export ScopeContract)")
      (write-source (path-expand "objects.ss" chosen)
        "(import :clan/poo/object) (def Scope (.o unused: (error \"scope forced\"))) (export Scope)")
      (write-source (path-expand "config.ss" chosen) "(def Enabled #t) (export Enabled)")
      (write-source (path-expand "interface.ss" chosen)
        "(.def Chosen identity: 'chosen core: (.o requires: (.o) scope-contract: ScopeContract exports: Scope) features: (.o))")
      (write-source (path-expand "tests/atomic-test.ss" chosen)
        "(begin-syntax (error \"test expanded during discovery\"))")
      (def previous 1)
      (def baseline #f)
      (def previous-guard #f)
      (for-each
       (lambda (size)
         (for-each
          (lambda (index)
            (def directory (path-expand (string-append "modules/unused-" (number->string index)) root))
            (for-each (lambda (role)
                        (write-source (path-expand role directory)
                          "(begin-syntax (error \"unselected role expanded\"))"))
              '("types.ss" "objects.ss" "config.ss" "interface.ss")))
          (iota (- size previous) previous))
         ;; Namespace changes invalidate the old snapshot even though every
         ;; selected body is unchanged. Narrow source support is not permission
         ;; to retain obsolete directory/selection authority.
         (when previous-guard
           (check-exception (previous-guard)
             (lambda (exception)
               (and (Error? exception)
                    (string=? (Error-message exception) "stale module scope generation")))))
         (set! previous size)
         (def body-reads 0)
         (def unused-reads 0)
         (def selection
           (parameterize ((current-module-source-observer
                           (lambda (key _amount)
                             (when (and (pair? key) (eq? (car key) 'file-read)
                                        (string-prefix? (path-expand "modules/" root) (caddr key)))
                               (set! body-reads (+ body-reads 1))
                               (unless (string-prefix? chosen (caddr key))
                                 (set! unused-reads (+ unused-reads 1)))))))
             (def view (yuanxu-load-modules (path-expand "init.ss" root)))
             (check-equal? (length (.all-slots (.get view modules))) size)
             (def tests (module-test-projection view '(chosen)))
             (check-equal? (.get tests spec) (list (path-expand "tests/atomic-test.ss" chosen)))
             (.call tests admit-current)
             (set! previous-guard (.get tests admit-current))
             view))
         (check-equal? unused-reads 0)
         (check-equal? (> body-reads 0) #t)
         (check-equal? (.ref/cached selection 'selected-graph) #f)
         ;; Runtime selection.modules returns a linked scope, not init's Module
         ;; view. Do not force it merely to inspect a nonexistent scope slot.
         ;; The declaration-scale fixture tests init's actual cold scope.
         (if baseline (check-equal? body-reads baseline) (set! baseline body-reads))
         (yuanxu-test-observe 'catalog-modules size)
         (yuanxu-test-observe 'selected-body-reads body-reads))
       '(1000 10000)))
    (yuanxu-test-case "complete selected stars visit each declaration once and preserve shared dependencies"
      (for-each
       (lambda (size)
         (def ids (map (lambda (index) (string->symbol (string-append "module-" (number->string index)))) (iota size)))
         (def calls (make-hash-table-eq))
         (def shared (car ids))
         (def completed 0)
         (def (read-publication id)
           (hash-update! calls id (cut + <> 1) 0)
           (def declaration
             (.o identity: id features: (.o)
                 core: (.o requires: (if (eq? id shared) (.o)
                                        (.o Shared: (.o module-id: shared)))
                           exports: (error "resolver linked business scope"))))
           ;; A completed batch of actual publications is work progress, not a
           ;; timer or output heartbeat. Exact-once counts are asserted below.
           (set! completed (1+ completed))
           (when (zero? (modulo completed 64))
             (execution-progress! (list 'declaration-batch size) completed))
           declaration)
         (def graph
           (select-module-graph
             (.o selected: ids denied-modules: '() generation: "scale")
             ids read-publication void))
         (check-equal? (length (.get graph module-order)) size)
         (check-equal? (car (.get graph module-order)) shared)
         (check-equal? (hash-length calls) size)
         (for-each (lambda (id) (check-equal? (hash-ref calls id) 1)) ids)
         ;; The production DFS is iterative even for a deep closure. Shared
         ;; edges and a cycle must not re-enter the import accessor.
         (def edges 0)
         (check-equal?
           (length (module-closure '(0) identity
                     (lambda (node)
                       (set! edges (+ edges 1))
                       (when (zero? (modulo edges 64))
                         (execution-progress! (list 'deep-closure-batch size) edges))
                       (if (< node (- size 1)) (list (+ node 1) 0) '())))) size)
         (check-equal? edges size)
         (yuanxu-test-observe 'selected-declarations (hash-length calls))
         (yuanxu-test-observe 'deep-closure-visits edges))
       '(1000 10000)))))
