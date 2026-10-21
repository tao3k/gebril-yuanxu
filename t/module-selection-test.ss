;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o .ref)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/selection/objects
        :yuanxu/module-system/selection/contract
        :yuanxu/module-system/selection/syntax
        :yuanxu/profile-composition/user-profile)
(export module-selection-test)
(def module-selection-test
  (test-suite "Core declarations keep repository policy scoped and values inert"
    (yuanxu-test-case "module routing is supplied by the owner, never guessed globally"
      (let (policy (.o groups: (.o library: 'example)))
        (check-equal? (yuanxu-modules-system-use-module-group 'library) 'custom)
        (parameterize ((current-module-selection-policy policy))
          (let (rows (yuanxu-modules-system-use-module/contract 'library '(-unused)))
            (check-equal? (yuanxu-user-module-selection-key (car rows)) '(example . library))
            (check-equal? (yuanxu-user-module-selection-flags (car rows)) '(-unused))))
        (check-equal? (yuanxu-modules-system-use-module-group 'library) 'custom)))
    (yuanxu-test-case "native Profile composition remains provider independent"
      (let* ((rows (yuanxu-modules! :custom (library -unused)))
             (profile (yuanxuUserProfile 'example rows (yuanxu-settings address: "localhost") '(address))))
        (check-equal? (yuanxu-user-profile-name profile) 'example)
        (check-equal? (length (yuanxu-user-profile-modules profile)) 1)
        (check-equal? (.ref (yuanxu-user-profile-settings profile) 'address) "localhost")))))
