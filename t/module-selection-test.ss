;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o .ref)
        (only-in :core/observability/testing-case poo-flow-test-case)
        :core/module-system/selection/objects
        :core/module-system/selection/contract
        :core/module-system/selection/syntax
        :core/profile-composition/user-profile)
(export module-selection-test)
(def module-selection-test
  (test-suite "Core declarations keep repository policy scoped and values inert"
    (poo-flow-test-case "module routing is supplied by the owner, never guessed globally"
      (let (policy (.o groups: (.o library: 'example)))
        (check-equal? (poo-flow-modules-system-use-module-group 'library) 'custom)
        (parameterize ((current-module-selection-policy policy))
          (let (rows (poo-flow-modules-system-use-module/contract 'library '(-unused)))
            (check-equal? (poo-flow-user-module-selection-key (car rows)) '(example . library))
            (check-equal? (poo-flow-user-module-selection-flags (car rows)) '(-unused))))
        (check-equal? (poo-flow-modules-system-use-module-group 'library) 'custom)))
    (poo-flow-test-case "native Profile composition remains provider independent"
      (let* ((rows (poo-flow-modules! :custom (library -unused)))
             (profile (pooFlowUserProfile 'example rows (poo-flow-settings address: "localhost") '(address))))
        (check-equal? (poo-flow-user-profile-name profile) 'example)
        (check-equal? (length (poo-flow-user-profile-modules profile)) 1)
        (check-equal? (.ref (poo-flow-user-profile-settings profile) 'address) "localhost")))))
