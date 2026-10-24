;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/module-system/building/artifacts admit-build-artifacts!))
(export build-recovery-boundary-test)
(def build-recovery-boundary-test
  (test-suite "Selected publication recovery boundary"
    (test-case "a no-op cannot turn managed recovery into source-only publication"
      (def calls 0)
      (def graph (.o build-publication:
        (.o .restore-build: (lambda (_graph) (set! calls (+ calls 1))))))
      (def failure (with-catch values (cut admit-build-artifacts! graph)))
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "selected build publication did not restore issuance")
      (check-exception (admit-build-artifacts! graph) Error?)
      (check-equal? calls 1))
    (test-case "recursive recovery is refused and does not retry the Source"
      (def calls 0)
      (def graph (.o build-publication:
        (.o .restore-build:
          (lambda (receiver) (set! calls (+ calls 1)) (admit-build-artifacts! receiver)))))
      (def failure (with-catch values (cut admit-build-artifacts! graph)))
      (check-equal? (Error? failure) #t)
      (check-equal? (Error-message failure) "recursive Core build recovery")
      (check-exception (admit-build-artifacts! graph) Error?)
      (check-equal? calls 1))
    (test-case "ordinary source-only publication remains inert"
      (check-equal? (void? (admit-build-artifacts! (.o))) #t))))
