;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o .ref)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/config)

(export module-interface-test)

(def module-interface-test
  (test-suite "Core Module Interface mechanism"
    (yuanxu-test-case "schema indexing and option policy are product-neutral"
      (let* ((schema (.o (endpoint (yuanxu-string-required))))
             (index (yuanxu-module-interface-schema-index schema))
             (append-policy (yuanxu-option-append 'String '())))
        (check-equal? (.ref (hash-get index "endpoint") 'type) 'String)
        (check-equal? (.ref append-policy 'policy) 'append)
        (check-equal? (yuanxu-module-kind=? "core.module" "core.module") #t)))
    (yuanxu-test-case "object inspection keeps declared slot values"
      (check-equal? (yuanxu-module-object->alist (.o identity: 'core))
                    '((identity . core))))))
