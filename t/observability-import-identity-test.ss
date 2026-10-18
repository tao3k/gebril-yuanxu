;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Import the factory before its public descriptor: source and compiled owners
;;; must not replace a prototype after the factory has retained that reference.
(import :std/test :clan/poo/object
        (only-in :core/observability/funcs poo-flow-debug-memory-policy)
        (only-in :core/observability/types PooFlowDebugMemoryPolicyContract))
(export observability-import-identity-test)
(def observability-import-identity-test
  (test-suite "public descriptor and retained factory prototype identity"
    (test-case "memory policy factory retains the public descriptor prototype"
      (def policy
        (poo-flow-debug-memory-policy 'import-identity
          heap-limit-bytes: 1073741824 live-growth-limit-bytes: 536870912))
      (check-equal?
        (and (memq (.get PooFlowDebugMemoryPolicyContract proto)
                   (compute-precedence-list! policy)) #t) #t))))
