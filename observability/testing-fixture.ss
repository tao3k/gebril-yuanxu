;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .call)
        (only-in :core/ops/progress call-with-execution-cancellation)
        (only-in "./testing-case.ss" poo-flow-test-case poo-flow-test-case/with))
(export call-with-poo-flow-fixture with-poo-flow-fixture poo-flow-test-fixture)

;; Acquisition owns rollback if it fails before returning a resource. Cleanup
;; runs for a returned resource even when body raises; neither failure is hidden.
(def (call-with-poo-flow-fixture fixture procedure)
  (call-with-execution-cancellation
    (lambda ()
      (let ((resource (.call fixture .acquire)) (body-failure #f))
        (dynamic-wind void
          (lambda ()
            (with-catch
              (lambda (exception) (set! body-failure exception) (raise exception))
              (lambda () (procedure resource))))
          (lambda ()
            (with-catch
              (lambda (cleanup-failure)
                (if body-failure
                  (error "fixture body and cleanup failed" body-failure cleanup-failure)
                  (raise cleanup-failure)))
              (lambda () (.call fixture .release resource)))))))))

(defrules with-poo-flow-fixture ()
  ((_ (binding fixture) body ...)
   (call-with-poo-flow-fixture fixture (lambda (binding) body ...))))
(defrules poo-flow-test-fixture ()
  ((_ description profile: profile (binding fixture) body ...)
   (poo-flow-test-case/with profile description
     (with-poo-flow-fixture (binding fixture) body ...)))
  ((_ description (binding fixture) body ...)
   (poo-flow-test-case description
     (with-poo-flow-fixture (binding fixture) body ...))))
