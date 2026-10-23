;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :clan/poo/object .call)
        (only-in :yuanxu/ops/progress call-with-execution-cancellation)
        (only-in "./testing-case.ss" yuanxu-test-case yuanxu-test-case/with
                 yuanxu-test-checkpoint))
(export call-with-yuanxu-fixture with-yuanxu-fixture yuanxu-test-fixture)

;; Acquisition owns rollback if it fails before returning a resource. Cleanup
;; runs for a returned resource even when body raises; neither failure is hidden.
(def (call-with-yuanxu-fixture fixture procedure)
  (call-with-execution-cancellation
    (lambda ()
      (let ((resource (.call fixture .acquire)) (body-failure #f))
        (dynamic-wind void
          (lambda ()
            (with-catch
              (lambda (exception) (set! body-failure exception) (raise exception))
              (lambda ()
                ;; The cleanup extent already owns resource before observation.
                (yuanxu-test-checkpoint 'fixture-acquired)
                (begin0 (procedure resource)
                  (yuanxu-test-checkpoint 'fixture-body-returned)))))
          (lambda ()
            (with-catch
              (lambda (cleanup-failure)
                (if body-failure
                  (error "fixture body and cleanup failed" body-failure cleanup-failure)
                  (raise cleanup-failure)))
              (lambda ()
                (begin0 (.call fixture .release resource)
                  (yuanxu-test-checkpoint 'fixture-released))))))))))

(defrules with-yuanxu-fixture ()
  ((_ (binding fixture) body ...)
   (call-with-yuanxu-fixture fixture (lambda (binding) body ...))))
(defrules yuanxu-test-fixture ()
  ((_ description profile: profile (binding fixture) body ...)
   (yuanxu-test-case/with profile description
     (with-yuanxu-fixture (binding fixture) body ...)))
  ((_ description (binding fixture) body ...)
   (yuanxu-test-case description
     (with-yuanxu-fixture (binding fixture) body ...))))
