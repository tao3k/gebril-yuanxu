;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The init-owned atomic endpoint, with no external package realization.
(import :std/test :clan/poo/object
        (only-in "../init.ss" init.Scenarios))
(export aws-module-test)
(def aws-module-test
  (test-suite "AWS atomic endpoint"
    (test-case "cold discovery and repeated execution leave integration and scope cold"
      (def started (real-time))
      (def module (.get init.Scenarios aws))
      (def tests (.get module tests))
      (check-equal? (.ref/cached module 'scope) #f)
      (check-equal? (.ref/cached tests 'integration) #f)
      (def cold (.call tests .run))
      (def cold-total (- (real-time) started))
      (def warm-start (real-time))
      (def warm (.call tests .run))
      (displayln "AWS atomic seconds: cold=" cold-total
                 " warm=" (- (real-time) warm-start)
                 " workers=" (.get cold seconds) "/" (.get warm seconds))
      (check-equal? (.get cold status) 0)
      (check-equal? (.get warm status) 0)
      (check-equal? (.ref/cached tests 'integration) #f)
      (check-equal? (.ref/cached module 'scope) #f))
    (test-case "integration is an explicit lazy projection of the same Graph"
      (def module (.get init.Scenarios aws))
      (def tests (.get module tests))
      (def integration (.get tests integration))
      (check-equal? (eq? (.get tests selected-graph) (.get integration selected-graph)) #t)
      (check-equal? (map path-strip-directory (.get integration spec)) '("context-publication-test.ss"))
      (check-equal? (.ref/cached integration 'execution) #f)
      (check-equal? (.ref/cached module 'scope) #f))))
