;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: focused native test for the extension operation algebra.
;;; Invariant: this owner imports only the extension facade, so native gxtest
;;; cannot pass through a stale aggregate user-interface build.

(import (only-in :clan/poo/object .o .cc)
        (only-in :core/graph/operation poo-flow-graph-operation-prototype)
        (only-in :core/observability/testing-case poo-flow-test-case)
         (only-in :std/test
                 check-equal?
                 test-suite)
        :core/graph/interface)

(export module-extension-resolution-test graph-unification-test graph-native-operation-test)

;; : (-> PooFlowGraph Symbol MaybeAny)
(def (extension-slot-value node slot-name)
  (let (entry (assoc slot-name (poo-flow-graph-root-payload node)))
    (if entry (cdr entry) #f)))

;; : TestSuite
(def module-extension-resolution-test
  (test-suite "native POO module extension resolution"
    (poo-flow-test-case "dispatches ordered operations through native prototypes"
      (let* ((child
              (poo-flow-graph-rooted
               'workflow/build
               '((run . "gxi build.ss") (artifacts . ()))
               '()))
             (root
              (poo-flow-graph-rooted
               'workflow
               '((needs . (test)))
               (list child)))
             (result
              (poo-flow-graph-resolve
               root
               (list
                (poo-flow-graph-contribution
                 'workflow
                 (list
                  (poo-flow-graph-slot-prepend 'needs '(setup))
                  (poo-flow-graph-slot-append 'needs '(lint test))))
                (poo-flow-graph-contribution
                 'workflow/build
                 (list
                  (poo-flow-graph-slot-override
                   'run "gxi build.ss --optimized")
                  (poo-flow-graph-slot-append
                   'artifacts '(dist)))))))
             (resolved (poo-flow-graph-result-root result))
             (resolved-child
              (poo-flow-graph-root-ref
               (poo-flow-graph-root-children resolved)
               'workflow/build)))
        (check-equal? (poo-flow-graph-result-applied? result) #t)
        (check-equal? (poo-flow-graph-result-changed-passes result) 1)
        (check-equal? (extension-slot-value resolved 'needs)
                      '(setup test lint))
        (check-equal? (extension-slot-value resolved-child 'run)
                      "gxi build.ss --optimized")
        (check-equal? (extension-slot-value resolved-child 'artifacts)
                      '(dist))))
    (poo-flow-test-case "repeated idempotent append demand reports no change"
      (let* ((root
              (poo-flow-graph-rooted
               'workflow '((needs . (test lint))) '()))
             (contribution
              (poo-flow-graph-contribution
               'workflow
               (list
                (poo-flow-graph-slot-append
                 'needs '(lint test)))))
             (result
              (poo-flow-graph-resolve root (list contribution))))
        (check-equal? (poo-flow-graph-result-changed-passes result) 0)
        (check-equal?
         (extension-slot-value
          (poo-flow-graph-result-root result)
          'needs)
         '(test lint))))))

;; This fixture deliberately uses the public Graph algorithms on the same
;; objects consumed by operations; no extension-node projection is involved.
(def graph-unification-test
  (test-suite "one graph representation and ordered application"
    (poo-flow-test-case "path identities isolate equal local names"
      (let* ((root
              (poo-flow-graph-rooted 'root '()
                (list
                 (poo-flow-graph-rooted 'left '()
                   (list (poo-flow-graph-rooted 'leaf '((value . 0)) '())))
                 (poo-flow-graph-rooted 'right '()
                   (list (poo-flow-graph-rooted 'leaf '((value . 0)) '()))))))
             (result (poo-flow-graph-resolve root
                       (list (poo-flow-graph-contribution '(root left leaf)
                               (list (poo-flow-graph-slot-override 'value 7))))))
             (resolved (poo-flow-graph-result-root result))
             (left (car (poo-flow-graph-root-children resolved)))
             (right (cadr (poo-flow-graph-root-children resolved))))
        (check-equal? (poo-flow-graph? resolved) #t)
        (check-equal? (andmap poo-flow-graph-node? (poo-flow-graph-nodes resolved)) #t)
        (check-equal? (poo-flow-graph-node-ids resolved)
                      '((root) (root left) (root left leaf) (root right) (root right leaf)))
        (check-equal? (length (poo-flow-graph-reachable-ids resolved '((root)))) 5)
        (check-equal? (extension-slot-value (car (poo-flow-graph-root-children left)) 'value) 7)
        (check-equal? (extension-slot-value (car (poo-flow-graph-root-children right)) 'value) 0)))
    (poo-flow-test-case "removal drops the complete contained subtree"
      (let* ((root (poo-flow-graph-rooted 'root '()
                    (list (poo-flow-graph-rooted 'old '()
                            (list (poo-flow-graph-rooted 'leaf '() '())))
                          (poo-flow-graph-rooted 'keep '() '()))))
             (result (poo-flow-graph-resolve root
                       (list (poo-flow-graph-contribution 'root
                               (list (poo-flow-graph-node-remove 'old))))))
             (resolved (poo-flow-graph-result-root result)))
        (check-equal? (poo-flow-graph-node-ids resolved) '((root) (root keep)))
        (check-equal? (poo-flow-graph-edge-pairs resolved) '(((root) (root keep))))))
    (poo-flow-test-case "node extension preserves inherited slots and descendants"
      (let* ((root (poo-flow-graph-rooted 'root '()
                    (list (poo-flow-graph-rooted 'child '((kept . 1))
                            (list (poo-flow-graph-rooted 'leaf '() '()))))))
             (resolved
              (poo-flow-graph-result-root
               (poo-flow-graph-resolve root
                 (list (poo-flow-graph-contribution 'root
                         (list (poo-flow-graph-node-extend
                                 (poo-flow-graph-rooted 'child '((added . 2)) '()))))))))
             (child (car (poo-flow-graph-root-children resolved))))
        (check-equal? (extension-slot-value child 'kept) 1)
        (check-equal? (extension-slot-value child 'added) 2)
        (check-equal? (length (poo-flow-graph-root-children child)) 1)))
    (poo-flow-test-case "one completed pass does not claim convergence"
      (let* ((root (poo-flow-graph-rooted 'root '() '()))
             (contributions
              (list
               (poo-flow-graph-contribution 'new
                 (list (poo-flow-graph-slot-override 'observed #t)))
               (poo-flow-graph-contribution 'root
                 (list (poo-flow-graph-node-extend (poo-flow-graph-rooted 'new '() '()))))))
             (first (poo-flow-graph-resolve root contributions))
             (second (poo-flow-graph-resolve (poo-flow-graph-result-root first) contributions)))
        (check-equal? (poo-flow-graph-result-applied? first) #t)
        (check-equal? (extension-slot-value
                       (car (poo-flow-graph-root-children (poo-flow-graph-result-root first)))
                       'observed) #f)
        (check-equal? (extension-slot-value
                       (car (poo-flow-graph-root-children (poo-flow-graph-result-root second)))
                       'observed) #t)))))

(def graph-native-operation-test
  (test-suite "native Graph operation extension"
    (poo-flow-test-case "custom POO operation keeps graph and node metadata"
      (let* ((base (poo-flow-graph-rooted 'root '() '()))
             (annotated
              (.cc base metadata: '((owner . caller))
                   nodes: (list (.cc (car (poo-flow-graph-nodes base))
                                     metadata: '((origin . source))))))
             (operation
              (.o (:: self poo-flow-graph-operation-prototype)
                  (.apply (lambda (node)
                            (poo-flow-graph-root-replace
                             node '((custom . accepted))
                             (poo-flow-graph-root-children node))))))
             (resolved
              (poo-flow-graph-result-root
               (poo-flow-graph-resolve annotated
                 (list (poo-flow-graph-contribution 'root (list operation)))))))
        (check-equal? (extension-slot-value resolved 'custom) 'accepted)
        (check-equal? (poo-flow-graph-metadata resolved) '((owner . caller)))
        (check-equal? (poo-flow-graph-node-metadata (car (poo-flow-graph-nodes resolved)))
                      '((origin . source)))))))
