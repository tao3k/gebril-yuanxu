;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :yuanxu/observability/testing-case yuanxu-test-case)
         :std/test :std/error
        (only-in :clan/poo/object .o .ref .put!)
        :yuanxu/contribution/verification)
(export verification-test)

(def (snapshot value) (call-with-output-string (lambda (p) (write (.ref value 'claim) p))))
(def (operation value now until) (equal? (.ref value 'claim) "trusted"))
(def verification-test
  (test-suite "Sealed verification admission"
  (yuanxu-test-case "only issued matching receipts are admitted within their validity interval"
    (let* ((adapter (yuanxu-verification-adapter "test" operation snapshot))
           (claim (.o claim: "trusted"))
           (receipt (yuanxu-verify adapter claim 10 20)))
      (check-equal? (yuanxu-verification-valid? adapter receipt claim 10) #t)
      (check-equal? (yuanxu-verification-valid? adapter receipt claim 9) #f)
      (check-equal? (yuanxu-verification-valid? adapter receipt claim 20) #f)
      (check-equal? (yuanxu-verification-valid? adapter (.o (:: @ receipt)) claim 11) #f)
      (check-equal? (yuanxu-verification-valid? adapter receipt (.o claim: "forged") 11) #f)
      (.put! receipt 'expires-at 200)
      (check-equal? (yuanxu-verification-valid? adapter receipt claim 11) #f)))
  (yuanxu-test-case "revocation, issuer isolation and rejected operations are enforced"
    (let* ((a (yuanxu-verification-adapter "a" operation snapshot))
           (b (yuanxu-verification-adapter "b" operation snapshot))
           (claim (.o claim: "trusted")) (receipt (yuanxu-verify a claim 0 10)))
      (check-equal? (yuanxu-verification-valid? b receipt claim 1) #f)
      (check-equal? (yuanxu-verify a (.o claim: "forged" verified?: #t) 0 10) #f)
      (yuanxu-revoke-verification! a receipt)
      (check-equal? (yuanxu-verification-valid? a receipt claim 1) #f)
      (check-exception (yuanxu-verify a claim 10 10) Error?)))
  (yuanxu-test-case "forged and copied adapter presentations cannot validate a receipt"
    (let* ((adapter (yuanxu-verification-adapter "host" operation snapshot))
           (claim (.o claim: "trusted"))
           (receipt (yuanxu-verify adapter claim 0 10))
           (forged (.o identity: "host"
                       admits?: (lambda (receipt value now) #t)))
           (copied (.o (:: @ adapter))))
      (check-equal? (yuanxu-verification-valid? forged receipt claim 1) #f)
      (check-equal? (yuanxu-verification-valid? copied receipt claim 1) #f)
      (check-exception (yuanxu-verify forged claim 1 2) Error?)
      (.put! adapter 'identity "other")
      (check-equal? (yuanxu-verification-valid? adapter receipt claim 1) #f)))
  (yuanxu-test-case "an operation cannot change the value it is attesting"
    (let ((adapter (yuanxu-verification-adapter "mutating"
                     (lambda (v now until) (.put! v 'claim "changed") #t) snapshot)))
      (check-exception (yuanxu-verify adapter (.o claim: "trusted") 0 10) Error?)))
  (yuanxu-test-case "one indexed admission rejects omitted, cloned and subsequently revoked receipts"
    (let* ((adapter (yuanxu-verification-adapter "indexed" operation snapshot))
           (trusted (.o claim: "trusted"))
           (other (.o claim: "other"))
           (receipt (yuanxu-verify adapter trusted 0 10))
           (empty (yuanxu-verification-admission adapter '() 1))
           (cloned (yuanxu-verification-admission adapter (list (.o (:: @ receipt))) 1))
           (admission (yuanxu-verification-admission adapter (list receipt) 1)))
      (check-equal? (yuanxu-verification-admission-valid? empty trusted) #f)
      (check-equal? (yuanxu-verification-admission-valid? cloned trusted) #f)
      (check-equal? (yuanxu-verification-admission-valid? admission other) #f)
      (check-equal? (yuanxu-verification-admission-valid? admission trusted) #t)
      (check-equal?
       (yuanxu-verification-admission-valid?
        (.o identity: "indexed" instant: 1
            admits?: (lambda (value) #t)) trusted)
       #f)
      (check-equal?
       (yuanxu-verification-admission-valid?
        (.o (:: @ admission)) trusted)
       #f)
      (yuanxu-revoke-verification! adapter receipt)
      (check-equal? (yuanxu-verification-admission-valid? admission trusted) #f)))))
