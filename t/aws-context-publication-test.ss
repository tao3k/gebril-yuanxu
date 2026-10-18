;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification of the existing init-owned atomic test endpoint, not a runner.
(import (for-syntax "./qualification/aws-startup-observation.ss"))
(begin-syntax (aws-startup-observation-start!))
(import :std/test :clan/poo/object
        (only-in "../init.ss" init.Scenarios init.test-spec))
(begin-syntax (aws-startup-observation-finish!))
(export aws-context-publication-test)
(def aws-context-publication-test
  (test-suite "AWS tests are owned by the selected module namespace"
    (test-case "discovery stays cold and the existing Ops endpoint runs the atomic suite"
      (def started (real-time))
      (def previous started)
      (def (phase name)
        (when (getenv "CORE_AWS_TRACE" #f)
          (let (now (real-time))
            (displayln "AWS-ENTRY " name " elapsed=" (- now started)
                       " step=" (- now previous))
            (set! previous now)
            (force-output))))
      (phase 'imported)
      (def module (.get init.Scenarios aws))
      (phase 'namespace)
      (check-equal? (.ref/cached module 'scope) #f)
      (check-equal? (map path-strip-directory (init.test-spec '(aws))) '("atomic-test.ss"))
      (phase 'test-spec)
      (check-equal? (eq? (.get module tests selected-graph)
                        (.get module tests source selected-graph)) #t)
      (check-equal? (eq? (.get module tests selected-graph)
                        (.get module tests integration selected-graph)) #t)
      (phase 'execution-bound)
      (def result (.call (.get module tests integration) .run))
      (when (getenv "CORE_AWS_TRACE" #f) (display (.get result output)))
      (check-equal? (.ref/cached module 'scope) #f))))
