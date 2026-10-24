;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil/expander make-module-context module-context? module-context-import
                 make-module-import module-import? module-import-source
                 make-module-export module-export? module-export-context
                 make-import-set import-set? import-set-source)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case yuanxu-test-observe))
(export module-context-walk-test)

;; Independent original recursive oracle, used only on the small graph.
(def (recursive-context-walk root visit seen descend?)
  (let walk ((value root))
    (cond
     ((module-import? value) (walk (module-import-source value)))
     ((module-export? value) (walk (module-export-context value)))
     ((import-set? value) (walk (import-set-source value)))
     ((and (module-context? value) (not (hash-key? seen value)))
      (hash-put! seen value #t)
      (when (descend? value) (for-each walk (module-context-import value)))
      (visit value)))))
(def (context-node)
  ;; Same native names deliberately: graph identity is the context, not its id.
  ;; No SDK registry, import, evaluator, syntax body or runtime promise is edited.
  (make-module-context 'walk/same-name #f "walk/same-name" "context-fixture.ss"))
(def (wrapped context)
  (make-module-import
    (make-import-set (make-module-export context 'key 0 'key #f) 1 '()) 'key 1 #f))
(def module-context-walk-test
  (test-suite "SDK Context traversal correspondence"
    (yuanxu-test-case "postorder, wrappers, identity sharing and cuts match the original walk"
      (def nodes (list->vector (map (lambda (_) (context-node)) (iota 6))))
      (def (node n) (vector-ref nodes n))
      (slot-set! (node 0) 'import (list (wrapped (node 1)) (node 2)))
      (slot-set! (node 1) 'import (list (node 3)))
      (slot-set! (node 2) 'import (list (wrapped (node 3))))
      (slot-set! (node 3) 'import (list (node 1)))
      (slot-set! (node 4) 'import (list (node 2)))
      (for-each
        (lambda (cut)
          (def (descend? context) (not (eq? context cut)))
          (def expected '())
          (def actual '())
          (def expected-seen (make-hash-table-eq))
          (def actual-seen (make-hash-table-eq))
          (for-each
            (lambda (root)
              (recursive-context-walk root (lambda (value) (set! expected (cons value expected)))
                expected-seen descend?)
              (for-each-build-module root (lambda (value) (set! actual (cons value actual)))
                actual-seen descend?))
            (list (wrapped (node 0)) (node 4) (node 0)))
          (check-equal? actual expected)
          (check-equal? (hash-length actual-seen) (hash-length expected-seen))
          (check-equal? (hash-key? actual-seen (node 5)) #f))
        (list #f (node 1) (node 3))))
    (yuanxu-test-case "deep native context graphs use explicit frames and visit each identity once"
      (for-each
        (lambda (size)
          (def nodes (list->vector (map (lambda (_) (context-node)) (iota size))))
          (for-each
            (lambda (index)
              (slot-set! (vector-ref nodes index) 'import
                (if (< index (- size 1))
                  (list (wrapped (vector-ref nodes (+ index 1))) (vector-ref nodes 0))
                  (list (vector-ref nodes 0))))) (iota size))
          (def visits 0)
          (def descents 0)
          (def seen (make-hash-table-eq))
          (for-each-build-module (vector-ref nodes 0)
            (lambda (context)
              ;; The chain's exact postorder, not just a sorted node set.
              (check-equal? (eq? context (vector-ref nodes (- size visits 1))) #t)
              (set! visits (+ visits 1)))
            seen (lambda (_context) (set! descents (+ descents 1)) #t))
          (check-equal? visits size)
          (check-equal? descents size)
          (check-equal? (hash-length seen) size)
          (yuanxu-test-observe 'context-visits visits)
          (yuanxu-test-observe 'context-descents descents))
        '(1000 5000 10000)))))
