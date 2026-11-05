;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Atomic adapter to the installed Gerbil test tool; no test execution model.
(import (rename-in (only-in :gerbil/tools/gxtest main) (main gerbil-test-main))
        (only-in :std/os/pid getpid)
        (only-in :yuanxu/ops/progress
                 call-with-execution-watchdog execution-idle-seconds))
(export main)

(def (main . arguments)
  (displayln "test-entry pid=" (getpid))
  (force-output)
  ;; Pass official CLI arguments unchanged. The tool owns import, module hooks,
  ;; std/test discovery and every assertion. Never demand init or build here.
  ;; Just owns the invocation's total process fence; Case policies own their
  ;; semantic limits. Do not add a second, conflicting aggregate deadline.
  (call-with-execution-watchdog (* 1000 execution-idle-seconds) #f
    (lambda ()
      (let (status (apply gerbil-test-main arguments))
        (unless (eqv? status 0)
          (error "official test harness failed" arguments status))))))
