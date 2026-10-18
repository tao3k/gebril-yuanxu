;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :std/test test-suite check-equal?)
        :core/graph/interface
        :core/module-system/source/objects
        :core/module-system/source/projection)
(export graph-source-projection-test)
(def graph-source-projection-test
  (test-suite "SourceRef projection uses the unified Graph"
    (poo-flow-test-case "removal preserves source identity and remaining order"
      (let* ((first (make-poo-flow-module-source-ref 'local "first/config.ss" '()))
             (removed (make-poo-flow-module-source-ref 'local "removed/config.ss" '()))
             (last (make-poo-flow-module-source-ref 'local "last/config.ss" '()))
             (result
              (poo-flow-module-auto-imports-resolve
               (list first removed last)
               (list (poo-flow-graph-contribution 'auto-imports
                       (list (poo-flow-graph-node-remove "removed/config.ss"))))))
             (graph-value (poo-flow-graph-result-root result)))
        (check-equal? (poo-flow-graph? graph-value) #t)
        (check-equal? (poo-flow-module-auto-imports-result-source-refs result)
                      (list first last))
        (check-equal? (poo-flow-graph-node-ids graph-value)
                      '((auto-imports) (auto-imports "first/config.ss")
                        (auto-imports "last/config.ss")))
        (check-equal? (length (poo-flow-graph-edge-pairs graph-value)) 2)))))
