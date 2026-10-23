;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .mix .ref .ref/cached .cc)
        (only-in :clan/poo/mop element? validate TypeError?)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/schema/relations
                 yuanxu-semantic-identity yuanxu-module-imports)
        :yuanxu/module-system/types
        :yuanxu/module-system/objects)

(export module-system-semantic-test)

(def role
  (validate ModuleSourceRoleContract
    (.o (:: @ ModuleSourceRole.) identity: 'test
        recommended-forms: '()
        forbidden-slot-verbs: '()
        forbidden-root-forms: '()
        recursive-root-forms?: #f
        forbidden-imports: '()
        forbidden-forms: '()
        forbid-raw-behavior-hooks?: #f
        forbid-raw-query-initializers?: #f
        repair-operators: '()
        freedom: 'open)))

(def authoring
  (validate ModuleAuthoringProfileContract
    (.o (:: @ ModuleAuthoringProfile.) executor: (.o)
        types: role objects: role funs: role
        config: role interface: role)))

(def module-system-semantic-test
  (test-suite "Core semantic Module owner"
    (yuanxu-test-case "role fields use public value Types while Role admission retains Context"
      (check-equal? (eq? (validate ModuleSourceRoleContract role) role) #t)
      (check-equal? (element? ModuleSourceRoleContract (.cc role 'domain-policy 'extra)) #t)
      (check-exception (validate ModuleSourceRoleContract (.cc role 'forbidden-forms '(1))) TypeError?)
      (check-exception (validate ModuleSourceRoleContract (.cc role 'recursive-root-forms? 'false)) TypeError?)
      (check-exception (validate ModuleSourceRoleContract (.cc role 'freedom "open")) TypeError?)
      (check-exception (validate ModuleSourceRoleContract (.o)) TypeError?)
      (def unrelated (.o identity: (error "unrelated prototype field was forced")))
      (check-exception (validate ModuleSourceRoleContract unrelated) TypeError?)
      (check-equal? (.ref/cached unrelated 'identity) #f)
      (def context (.o identity: 'test/role-context))
      (def admitted (yuanxu-contract-admit ModuleAuthoringProfileContract authoring context))
      (def children (.ref admitted 'responsibility-evidence))
      (check-equal? (.ref admitted 'accepted?) #t)
      ;; Executor plus five Roles remain contextual children, not scalar receipts.
      (check-equal? (length children) 6)
      (for-each
        (lambda (child)
          (check-equal? (eq? (.ref child 'context) context) #t)
          (when (eq? (.ref child 'admission-contract) ModuleSourceRoleContract)
            (check-equal? (eq? (.ref child 'candidate) role) #t)
            (check-equal? (.ref child 'responsibility-evidence) '()))) children)
      (def rejecting
        ;; Refine policy for the SAME Role prototype, not a fresh nominal type.
        (.cc ModuleSourceRoleContract 'proto (.ref ModuleSourceRoleContract 'proto)
          '.obligations
          (lambda (_value actual-context)
            (if (eq? actual-context context) '(role-context-refused) '()))))
      (check-equal? (.ref (yuanxu-contract-admit rejecting role context) 'accepted?) #f)
      (check-equal? (.ref (yuanxu-contract-admit rejecting role #f) 'accepted?) #t))
    (yuanxu-test-case "generic constructor requires an admitted authoring Profile"
      (let* ((identity (yuanxu-semantic-identity 'core 'test))
             (left (make-semantic-module identity authoring))
             (right (make-semantic-module identity authoring)))
        (check-equal? (element? SemanticModuleContract left) #t)
        (check-equal? (.ref left 'authoring) authoring)
        (check-equal? (eq? (.ref left 'imports) (.ref right 'imports)) #f)
        (check-equal? (eq? (.ref left 'profiles) (.ref right 'profiles)) #f)
        (check-exception
         (make-semantic-module identity '()) TypeError?)
        (check-exception
         (validate SemanticModuleContract (.cc left 'identity 'invalid))
         TypeError?)))
    (yuanxu-test-case "leaf imports keep identity and C4 composes inherited imports"
      (let* ((identity (yuanxu-semantic-identity 'core 'test))
             (base-imports (yuanxu-module-imports 'base))
             (left-imports (yuanxu-module-imports 'left))
             (right-imports (yuanxu-module-imports 'right))
             (base (make-semantic-module identity authoring
                                         imports: base-imports))
             (left (.mix (make-semantic-module identity authoring
                                               imports: left-imports)
                         base))
             (right (.mix (make-semantic-module identity authoring
                                                imports: right-imports)
                          base))
             (combined (.mix left right)))
        (check-equal? (eq? (.ref base 'imports) base-imports) #t)
        (check-equal? (.ref (.ref combined 'imports) 'contributions)
                      '(left right base))))))
