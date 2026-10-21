;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :std/test test-suite check-equal?)
        :yuanxu/graph/interface
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/projection)
(export graph-source-projection-test)
(def graph-source-projection-test
  (test-suite "SourceRef projection uses the unified Graph"
    (yuanxu-test-case "removal preserves source identity and remaining order"
      (let* ((first (make-yuanxu-module-source-ref 'local "first/config.ss" '()))
             (removed (make-yuanxu-module-source-ref 'local "removed/config.ss" '()))
             (last (make-yuanxu-module-source-ref 'local "last/config.ss" '()))
             (result
              (yuanxu-module-auto-imports-resolve
               (list first removed last)
               (list (yuanxu-graph-contribution 'auto-imports
                       (list (yuanxu-graph-node-remove "removed/config.ss"))))))
             (graph-value (yuanxu-graph-result-root result)))
        (check-equal? (yuanxu-graph? graph-value) #t)
        (check-equal? (yuanxu-module-auto-imports-result-source-refs result)
                      (list first last))
        (check-equal? (yuanxu-graph-node-ids graph-value)
                      '((auto-imports) (auto-imports "first/config.ss")
                        (auto-imports "last/config.ss")))
        (check-equal? (length (yuanxu-graph-edge-pairs graph-value)) 2)))))
