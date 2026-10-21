;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: focused native test for module-object POO ancestry.
;;; Invariant: field resolution is delegated to gerbil-poo supers and C4.

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         (only-in :std/test
                 check-equal?
                 test-suite)
        :yuanxu/module-system/schema/interface
        :yuanxu/graph/interface)

(export module-object-native-inheritance-test)

;; : (-> Symbol Symbol PooModuleFieldContract)
(def (symbol-field name default)
  (yuanxu-module-field-contract
   name YuanxuModuleSymbolType 'override default '()))

;; : TestSuite
(def module-object-native-inheritance-test
  (test-suite "native POO module-object inheritance"
    (yuanxu-test-case "diamond field precedence follows native C4 supers"
      (let* ((root
              (yuanxu-module-object
               'object/root '()
               (list (symbol-field 'shared 'root)
                     (symbol-field 'root-only 'root-only))
               '()))
             (right
              (yuanxu-module-object
               'object/right (list root)
               (list (symbol-field 'shared 'right)
                     (symbol-field 'right-only 'right-only))
               '()))
             (left
              (yuanxu-module-object
               'object/left (list root)
               (list (symbol-field 'shared 'left)
                     (symbol-field 'left-only 'left-only))
               '()))
             (child
              (yuanxu-module-object
               'object/child (list left right)
               (list (symbol-field 'child-only 'child-only))
               '())))
        (check-equal?
         (map yuanxu-module-field-contract-identity
              (yuanxu-module-object-resolved-fields child))
         '(shared root-only right-only left-only child-only))
        (check-equal?
         (yuanxu-module-field-contract-default
          (yuanxu-module-object-field child 'shared))
         'left)
        (check-equal?
         (yuanxu-module-field-contract-default
          (yuanxu-module-object-field child 'right-only))
         'right-only)))
    (yuanxu-test-case "inconsistent native C4 ancestry is rejected"
      (let* ((root (yuanxu-module-object 'root '() '() '()))
             (a (yuanxu-module-object 'a (list root) '() '()))
             (b (yuanxu-module-object 'b (list root) '() '()))
             (x (yuanxu-module-object 'x (list a b) '() '()))
             (y (yuanxu-module-object 'y (list b a) '() '()))
             (broken (yuanxu-module-object 'broken (list x y) '() '()))
             (failure
              (with-catch
               (lambda (caught) caught)
               (lambda ()
                 (yuanxu-module-object-resolved-fields broken)
                 #f))))
        (check-equal? (not (not failure)) #t)))
    (yuanxu-test-case "root contributions leave the child-only fast path"
      (let* ((child
              (yuanxu-module-object
               'object/child '() (list (symbol-field 'marker 'base)) '()))
             (base (yuanxu-module-objects-node (list child)))
             (contributions
              (list
               (yuanxu-module-field-contribution
                'objects (symbol-field 'namespace 'objects) 'updated)
               (yuanxu-module-field-contribution
                'object/child (symbol-field 'marker 'base) 'changed)))
             (result
              (yuanxu-module-objects-resolve-contributions/node
               base contributions))
             (resolved (yuanxu-module-field-resolution-result-root result))
             (resolved-child
              (yuanxu-module-objects-ref resolved 'object/child)))
        (check-equal?
         (cdr (assoc 'namespace (yuanxu-graph-root-payload resolved)))
         'updated)
        (check-equal?
         (cdr (assoc 'marker
                     (yuanxu-graph-root-payload resolved-child)))
         'changed)
        (check-equal? (yuanxu-module-field-resolution-result-applied? result)
                      #t)))))
