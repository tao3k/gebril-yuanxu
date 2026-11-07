;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Explicit slot policies are pure values shared by Core and vertical modules.

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :std/test check-equal? test-suite)
        :yuanxu/module-system/schema/interface)

(export module-schema-slot-policy-test)

(def module-schema-slot-policy-test
  (test-suite "module schema slot policy"
    (yuanxu-test-case "override does not normalize scalar values"
      (check-equal?
       (yuanxu-module-slot-apply-policy 'override '(old) 'new)
       'new))
    (yuanxu-test-case "ordered list policies deduplicate and remove"
      (check-equal?
       (yuanxu-module-slot-apply-policy 'append '(a b) '(b c))
       '(a b c))
      (check-equal?
       (yuanxu-module-slot-apply-policy 'prepend '(a b) '(b c))
       '(b c a))
      (check-equal?
       (yuanxu-module-slot-apply-policy 'remove '(a b c) '(b))
       '(a c)))))
