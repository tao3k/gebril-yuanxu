;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o .ref)
        (only-in :tao3k/yuanxu/observability/testing-case yuanxu-test-case)
        :tao3k/yuanxu/module-system/graph/funs)

(export module-graph-test)

(def (key-of module) (.ref module 'name))
(def (imports-of module) (.ref module 'imports))
(def (inline-imports module)
  (filter (lambda (value) (not (symbol? value))) (imports-of module)))

;; Count real adjacency requests through the production closure's accessor.
;; This is a structural algorithm gate, separate from Interface expansion,
;; owner admission and the existing real-directory capacity Cases.
(def (check-indexed-closure roots expected-keys expected-edges)
  (def queries (make-hash-table-eq))
  (def bucket-reads 0)
  (def edges 0)
  (def result
    (module-closure roots key-of
      (lambda (node)
        (def key (key-of node))
        (set! bucket-reads (1+ bucket-reads))
        (hash-update! queries key (cut + <> 1) 0)
        (def dependencies (inline-imports node))
        (set! edges (+ edges (length dependencies)))
        dependencies)))
  (check-equal? (map key-of result) expected-keys)
  (check-equal? (hash-length queries) (length expected-keys))
  ;; Every key in this table has at least one request. Equal distinct and
  ;; total counts therefore prove exactly one request per reached owner.
  (check-equal? bucket-reads (hash-length queries))
  (check-equal? edges expected-edges))

(def (scale-key index)
  (string->symbol (string-append "owner-" (number->string index))))
(def (scale-node key dependencies)
  (.o name: key imports: dependencies))

(def module-graph-test
  (test-suite "Core Module closure"
    (yuanxu-test-case "depth-first inline closure is ordered and unique"
      (let* ((leaf (.o name: 'leaf imports: '()))
             (root (.o name: 'root imports: (list leaf leaf 'missing)))
             (closed (module-closure (list root) key-of inline-imports)))
        (check-equal? (map key-of closed) '(root leaf))
        (check-equal?
         (module-missing-imports closed key-of imports-of symbol? (lambda (x) x))
         '(((module . root) (import . missing))))))
    (yuanxu-test-case "ten thousand roots share one provider traversal"
      (def provider (.o name: (scale-key 0) imports: '()))
      (def nodes
        (cons provider
          (map (lambda (index)
                 (.o name: (scale-key index) imports: (list provider)))
               (cdr (iota 10000)))))
      ;; Sparse demand does not visit the other 9,998 declarations.
      (def demanded (list-ref nodes 9999))
      (check-indexed-closure (list demanded)
        (list (scale-key 9999) (scale-key 0)) 1)
      ;; One visited set spans ALL roots, not one set per root/provider.
      (check-indexed-closure nodes (map scale-key (iota 10000)) 9999))
    (yuanxu-test-case "ten thousand deep owners use bounded work frames"
      (def tail '())
      (for-each
        (lambda (index)
          (set! tail (list (scale-node (scale-key index) tail))))
        (iota 10000))
      (check-indexed-closure tail (map scale-key (reverse (iota 10000))) 9999))
    (yuanxu-test-case "cycles and repeated edges expand each owner once"
      (def nodes (make-hash-table-eq))
      (for-each
        (lambda (key)
          (hash-put! nodes key
            (.o name: key
                imports: (list (hash-ref nodes (if (eq? key 'left) 'right 'left))))))
        '(left right))
      (check-indexed-closure
        (list (hash-ref nodes 'left) (hash-ref nodes 'left)) '(left right) 2))))
