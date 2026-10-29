;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: focused native test for the extension operation algebra.
;;; Invariant: this owner imports only the extension facade, so native gxtest
;;; cannot pass through a stale aggregate user-interface build.

(import (only-in :clan/poo/object .o .cc)
        (only-in :yuanxu/graph/operation yuanxu-graph-operation-prototype)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         (only-in :std/test
                 check-equal?
                 check-exception
                 test-suite)
        :yuanxu/graph/interface
        (only-in :yuanxu/graph/payload-operations yuanxu-graph-slots-merge))

(export module-extension-resolution-test graph-unification-test graph-native-operation-test)

;; : (-> YuanxuGraph Symbol MaybeAny)
(def (extension-slot-value node slot-name)
  (let (entry (assoc slot-name (yuanxu-graph-root-payload node)))
    (if entry (cdr entry) #f)))

;; : TestSuite
(def module-extension-resolution-test
  (test-suite "native POO module extension resolution"
    (yuanxu-test-case "dispatches ordered operations through native prototypes"
      (let* ((child
              (yuanxu-graph-rooted
               'workflow/build
               '((run . "gxi build.ss") (artifacts . ()))
               '()))
             (root
              (yuanxu-graph-rooted
               'workflow
               '((needs . (test)))
               (list child)))
             (result
              (yuanxu-graph-resolve
               root
               (list
                (yuanxu-graph-contribution
                 'workflow
                 (list
                  (yuanxu-graph-slot-prepend 'needs '(setup))
                  (yuanxu-graph-slot-append 'needs '(lint test))))
                (yuanxu-graph-contribution
                 'workflow/build
                 (list
                  (yuanxu-graph-slot-override
                   'run "gxi build.ss --optimized")
                  (yuanxu-graph-slot-append
                   'artifacts '(dist)))))))
             (resolved (yuanxu-graph-result-root result))
             (resolved-child
              (yuanxu-graph-root-ref
               (yuanxu-graph-root-children resolved)
               'workflow/build)))
        (check-equal? (yuanxu-graph-result-applied? result) #t)
        (check-equal? (yuanxu-graph-result-changed-passes result) 1)
        (check-equal? (extension-slot-value resolved 'needs)
                      '(setup test lint))
        (check-equal? (extension-slot-value resolved-child 'run)
                      "gxi build.ss --optimized")
        (check-equal? (extension-slot-value resolved-child 'artifacts)
                      '(dist))))
    (yuanxu-test-case "repeated idempotent append demand reports no change"
      (let* ((root
              (yuanxu-graph-rooted
               'workflow '((needs . (test lint))) '()))
             (contribution
              (yuanxu-graph-contribution
               'workflow
               (list
                (yuanxu-graph-slot-append
                 'needs '(lint test)))))
             (result
              (yuanxu-graph-resolve root (list contribution))))
        (check-equal? (yuanxu-graph-result-changed-passes result) 0)
        (check-equal?
         (extension-slot-value
          (yuanxu-graph-result-root result)
          'needs)
         '(test lint))))))

;; This fixture deliberately uses the public Graph algorithms on the same
;; objects consumed by operations; no extension-node projection is involved.
(def graph-unification-test
  (test-suite "one graph representation and ordered application"
    (yuanxu-test-case "path identities isolate equal local names"
      (let* ((root
              (yuanxu-graph-rooted 'root '()
                (list
                 (yuanxu-graph-rooted 'left '()
                   (list (yuanxu-graph-rooted 'leaf '((value . 0)) '())))
                 (yuanxu-graph-rooted 'right '()
                   (list (yuanxu-graph-rooted 'leaf '((value . 0)) '()))))))
             (result (yuanxu-graph-resolve root
                       (list (yuanxu-graph-contribution '(root left leaf)
                               (list (yuanxu-graph-slot-override 'value 7))))))
             (resolved (yuanxu-graph-result-root result))
             (left (car (yuanxu-graph-root-children resolved)))
             (right (cadr (yuanxu-graph-root-children resolved))))
        (check-equal? (yuanxu-graph? resolved) #t)
        (check-equal? (andmap yuanxu-graph-node? (yuanxu-graph-nodes resolved)) #t)
        (check-equal? (yuanxu-graph-node-ids resolved)
                      '((root) (root left) (root left leaf) (root right) (root right leaf)))
        (check-equal? (length (yuanxu-graph-reachable-ids resolved '((root)))) 5)
        (check-equal? (extension-slot-value (car (yuanxu-graph-root-children left)) 'value) 7)
        (check-equal? (extension-slot-value (car (yuanxu-graph-root-children right)) 'value) 0)))
    (yuanxu-test-case "unchanged root IDs still normalize noncanonical contained paths"
      ;; A same-ID fast path must inspect the facts rather than silently retain
      ;; a foreign prefix. The caller's original object remains untouched.
      (def original-node (yuanxu-graph-node '(foreign child) '((kept . 1))))
      (def child
        (yuanxu-graph '(root child) (list original-node) '() '((source . retained))))
      (def root (yuanxu-graph-rooted 'root '() (list child)))
      (def attached (car (yuanxu-graph-root-children root)))
      (check-equal? (yuanxu-graph-node-ids attached) '((root child)))
      (check-equal? (yuanxu-graph-metadata child) '((source . retained)))
      (check-equal? (yuanxu-graph-node-id original-node) '(foreign child))
      (check-equal? (extension-slot-value attached 'kept) 1))
    (yuanxu-test-case "removal drops the complete contained subtree"
      (let* ((root (yuanxu-graph-rooted 'root '()
                    (list (yuanxu-graph-rooted 'old '()
                            (list (yuanxu-graph-rooted 'leaf '() '())))
                          (yuanxu-graph-rooted 'keep '() '()))))
             (result (yuanxu-graph-resolve root
                       (list (yuanxu-graph-contribution 'root
                               (list (yuanxu-graph-node-remove 'old))))))
             (resolved (yuanxu-graph-result-root result)))
        (check-equal? (yuanxu-graph-node-ids resolved) '((root) (root keep)))
        (check-equal? (yuanxu-graph-edge-pairs resolved) '(((root) (root keep))))))
    (yuanxu-test-case "node extension preserves inherited slots and descendants"
      (let* ((root (yuanxu-graph-rooted 'root '()
                    (list (yuanxu-graph-rooted 'child '((kept . 1))
                            (list (yuanxu-graph-rooted 'leaf '() '()))))))
             (resolved
              (yuanxu-graph-result-root
               (yuanxu-graph-resolve root
                 (list (yuanxu-graph-contribution 'root
                         (list (yuanxu-graph-node-extend
                                 (yuanxu-graph-rooted 'child '((added . 2)) '()))))))))
             (child (car (yuanxu-graph-root-children resolved))))
        (check-equal? (extension-slot-value child 'kept) 1)
        (check-equal? (extension-slot-value child 'added) 2)
        (check-equal? (length (yuanxu-graph-root-children child)) 1)))
    (yuanxu-test-case "one completed pass does not claim convergence"
      (let* ((root (yuanxu-graph-rooted 'root '() '()))
             (contributions
              (list
               (yuanxu-graph-contribution 'new
                 (list (yuanxu-graph-slot-override 'observed #t)))
               (yuanxu-graph-contribution 'root
                 (list (yuanxu-graph-node-extend (yuanxu-graph-rooted 'new '() '()))))))
             (first (yuanxu-graph-resolve root contributions))
             (second (yuanxu-graph-resolve (yuanxu-graph-result-root first) contributions)))
        (check-equal? (yuanxu-graph-result-applied? first) #t)
        (check-equal? (extension-slot-value
                       (car (yuanxu-graph-root-children (yuanxu-graph-result-root first)))
                       'observed) #f)
        (check-equal? (extension-slot-value
                       (car (yuanxu-graph-root-children (yuanxu-graph-result-root second)))
                       'observed) #t)))))

(def graph-native-operation-test
  (test-suite "native Graph operation extension"
    (yuanxu-test-case "custom POO operation keeps graph and node metadata"
      (let* ((base (yuanxu-graph-rooted 'root '() '()))
             (annotated
              (.cc base metadata: '((owner . caller))
                   nodes: (list (.cc (car (yuanxu-graph-nodes base))
                                     metadata: '((origin . source))))))
             (operation
              (.o (:: self yuanxu-graph-operation-prototype)
                  (.apply (lambda (node)
                            (yuanxu-graph-root-replace
                             node '((custom . accepted))
                             (yuanxu-graph-root-children node))))))
             (resolved
              (yuanxu-graph-result-root
               (yuanxu-graph-resolve annotated
                 (list (yuanxu-graph-contribution 'root (list operation)))))))
        (check-equal? (extension-slot-value resolved 'custom) 'accepted)
        (check-equal? (yuanxu-graph-metadata resolved) '((owner . caller)))
        (check-equal? (yuanxu-graph-node-metadata (car (yuanxu-graph-nodes resolved)))
                      '((origin . source)))))
    (yuanxu-test-case "child views preserve fact order across shared cyclic descendants"
      ;; Publication order deliberately differs from traversal order. A view
      ;; includes shared reachable facts, excludes unrelated branches, and
      ;; retains the caller's node identities and graph metadata.
      (let* ((leaf (yuanxu-graph-node '(root leaf) '((value . kept))))
             (base (yuanxu-graph '(root)
                     (list leaf
                           (yuanxu-graph-node '(root b))
                           (yuanxu-graph-node '(root))
                           (yuanxu-graph-node '(root a)))
                     (list (yuanxu-graph-edge '(root a) '(root leaf))
                           (yuanxu-graph-edge '(root) '(root b))
                           (yuanxu-graph-edge '(root b) '(root leaf))
                           (yuanxu-graph-edge '(root) '(root a))
                           (yuanxu-graph-edge '(root leaf) '(root a)))
                     '((owner . original))))
             (children (yuanxu-graph-root-children base))
             (left (car children))
             (right (cadr children)))
        (check-equal? (map yuanxu-graph-root-id children) '(b a))
        (check-equal? (yuanxu-graph-node-ids left)
                      '((root leaf) (root b) (root a)))
        (check-equal? (yuanxu-graph-edge-pairs left)
                      '(((root a) (root leaf))
                        ((root b) (root leaf))
                        ((root leaf) (root a))))
        (check-equal? (yuanxu-graph-node-ids right) '((root leaf) (root a)))
        (check-equal? (yuanxu-graph-edge-pairs right)
                      '(((root a) (root leaf)) ((root leaf) (root a))))
        (check-equal? (eq? (car (yuanxu-graph-nodes right)) leaf) #t)
        (check-equal? (yuanxu-graph-metadata right) '((owner . original)))
        (check-equal? (length (yuanxu-graph-nodes base)) 4)))

    (yuanxu-test-case "slot merge retains duplicate positions and false overrides"
      (let ((base '((kept . #t) (duplicate . initial) (duplicate . shadow)))
            (extra '((duplicate . #f) (added . first) (added . #f) (last . final))))
        (check-equal? (yuanxu-graph-slots-merge base extra)
                      '((kept . #t) (duplicate . #f) (duplicate . shadow)
                        (added . #f) (last . final)))
        (check-equal? base '((kept . #t) (duplicate . initial) (duplicate . shadow)))
        (check-equal? extra '((duplicate . #f) (added . first) (added . #f) (last . final))))
      ;; Matching the first entry must never hide a malformed later declaration.
      (check-exception
       (yuanxu-graph-slots-merge '((duplicate . initial) malformed) '((duplicate . changed)))
       (lambda (_) #t)))
))
