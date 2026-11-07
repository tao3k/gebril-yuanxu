;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :clan/poo/object .o .mix .ref)
        (only-in :clan/poo/mop element? validate TypeError?)
        (only-in :std/test test-suite check-equal? check-exception)
        :yuanxu/module-system/schema/relations)
(export module-schema-relations-test)

(def module-schema-relations-test
  (test-suite "Core module relations"
    (yuanxu-test-case "identity and directional relations are POO values"
      (let* ((identity (yuanxu-semantic-identity 'test 'module))
             (imports (yuanxu-empty-imports))
             (profiles (yuanxu-empty-profiles))
             (capabilities (yuanxu-empty-capabilities)))
        (check-equal? (element? ModuleIdentityContract identity) #t)
        (check-equal? (element? ModuleImportsContract imports) #t)
        (check-equal? (element? ModuleProfilesContract profiles) #t)
        (check-equal? (element? ModuleImportsContract profiles) #f)
        (check-equal? (element? ModuleCapabilitiesContract capabilities) #t)
        (check-equal? (eq? imports (yuanxu-empty-imports)) #f)
        (check-exception
         (validate ModuleIdentityContract (.o namespace: 'test name: 42))
         TypeError?)))
    (yuanxu-test-case "contributions retain identity hops and lazy targets"
      (let* ((identity (yuanxu-semantic-identity 'test 'module))
             (target (lambda () (error "target was forced")))
             (contribution
              (yuanxu-import-contribution
               identity identity identity identity 'rev target))
             (imports (yuanxu-module-imports contribution)))
        (check-equal? (element? ImportContributionContract contribution) #t)
        (check-equal? (eq? (.ref contribution 'target) target) #t)
        (check-equal? (element? ModuleImportsContract imports) #t)
        (check-equal? (.ref imports 'contributions) (list contribution))))
    (yuanxu-test-case "C4 imports retain every distinct prototype contribution"
      (let* ((base (yuanxu-module-imports 'base))
             (left (.mix (yuanxu-module-imports 'left) base))
             (right (.mix (yuanxu-module-imports 'right) base))
             (combined (.mix left right)))
        (check-equal? (.ref combined 'contributions) '(left right base))))))
