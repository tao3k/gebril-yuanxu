;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .ref)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/profile-composition/profile-bundle)

(export profile-composition-test)

(def audit-profile
  (.o identity: 'audit imports: '(evidence) capabilities: '(read)))

(def govern-profile
  (.o identity: 'govern imports: '(policy) capabilities: '(decide)))

(def profile-composition-test
  (test-suite "Core ProfileBundle composition"
    (yuanxu-test-case "direct Profiles compose without a Scenario runtime"
      (let (bundle (compose profiles audit-profile govern-profile))
        (check-equal? (yuanxu-profile-bundle? bundle) #t)
        (check-equal? (.ref bundle 'profile-identities) '(audit govern))
        (check-equal? (.ref bundle 'imports) '(evidence policy))
        (check-equal? (.ref bundle 'capabilities) '(read decide))
        (check-equal? (.ref bundle 'runtime-executed?) #f)))
    (yuanxu-test-case "same Profile identity is idempotent"
      (let (bundle (compose profiles audit-profile audit-profile))
        (check-equal? (.ref bundle 'profile-identities) '(audit))))
    (yuanxu-test-case "distinct values with one identity conflict"
      (check-exception
       (compose profiles audit-profile (.o identity: 'audit))
       true))
    (yuanxu-test-case "indexed Module exports remain inert"
      (let (exports
            (yuanxu-module-profiles
             (yuanxu-profile-export 'audit audit-profile)
             (yuanxu-profile-export 'govern govern-profile)))
        (check-equal? (map (lambda (value) (.ref value 'identity))
                           (.ref exports 'contributions))
                      '(audit govern))))))
