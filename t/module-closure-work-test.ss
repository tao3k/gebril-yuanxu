;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :yuanxu/module-system/graph/funs module-closure)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-observe))
(export module-closure-work-test)

;; Independent finite saturation oracle; no DFS stack or production index.
(def (closure-oracle roots nodes dependencies)
  (let loop ((region roots))
    (def next
      (filter (lambda (candidate)
                (or (memv candidate region)
                    (ormap (lambda (parent) (memv candidate (dependencies parent))) region)))
              nodes))
    (if (equal? next region) region (loop next))))

(def module-closure-work-test
  (test-suite "Source closure algorithm work correspondence"
    (yuanxu-test-case "Quint shared diamond and cycle match independent saturation"
      (def nodes '(0 1 2 3 4 5))
      (def (dependencies node)
        (case node ((0) '(1 2)) ((1 2) '(3)) ((3) '(1)) ((4) '(2)) (else '())))
      (for-each
        (lambda (roots)
          (def result (module-closure roots identity dependencies))
          (check-equal? (filter (cut memv <> result) nodes)
                        (closure-oracle roots nodes dependencies))
          (check-equal? (memv 5 result) #f))
        '((0) (4) (0 4))))
    (yuanxu-test-case "thousand-scale work is roots plus traversed edges, not repeated expansion"
      (for-each
        (lambda (size)
          (def pops 0)
          (def expansions 0)
          (def charged-edges 0)
          (def counts (make-hash-table-eq))
          (def roots (list 0 (- size 1) (- size 1)))
          (def result
            (module-closure roots
              (lambda (node) (set! pops (+ pops 1)) node)
              (lambda (node)
                (set! expansions (+ expansions 1))
                (hash-update! counts node (cut + <> 1) 0)
                ;; Deep chain plus shared roots/back-edges; no recursive
                ;; Scheme caller stack and no unrelated business scope.
                (def children
                  (if (< node (- size 1)) (list (+ node 1) 0 (- size 1)) '(0)))
                (set! charged-edges (+ charged-edges (length children)))
                children)))
          (check-equal? result (iota size))
          (check-equal? expansions size)
          (check-equal? (hash-length counts) size)
          (for-each (lambda (node) (check-equal? (hash-ref counts node) 1)) result)
          (check-equal? pops (+ (length roots) charged-edges))
          (check-equal? charged-edges (+ (* 3 (- size 1)) 1))
          (yuanxu-test-observe 'closure-expansions expansions)
          (yuanxu-test-observe 'closure-pops pops)
          (yuanxu-test-observe 'closure-edges charged-edges))
        '(1000 5000 10000)))))
