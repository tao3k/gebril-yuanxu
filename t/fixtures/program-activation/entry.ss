prelude: :gerbil/core
package: tao3k/yuanxu/t/fixtures/program-activation
;;; SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
(import (only-in :std/os/time current-system-time-coarse timeval?)
        (for-syntax :gerbil/expander))
(export main)
;; Model a macro registering a role for linking without requesting activation.
(begin-syntax
  (parameterize ((current-expander-phi 0))
    (core-expand '(import (runtime: :tao3k/yuanxu/t/fixtures/program-activation/role)
                          (runtime: :tao3k/yuanxu/t/fixtures/program-activation/failure)))))

(def (activation)
  (##global-var-ref (##make-global-var 'tao3k/yuanxu/t/fixtures/program-activation/role#activation)))

(def (main . _)
  (unless (timeval? (current-system-time-coarse))
    (error "bootstrap lost the nested FFI superclass"))
  (unless (##unbound? (activation)) (error "link-only role initialized before demand"))
  (load-module "tao3k/yuanxu/t/fixtures/program-activation/role~0")
  (let (first (activation))
    (unless (equal? first '(42)) (error "runtime dependency was not activated before role" first))
    (load-module "tao3k/yuanxu/t/fixtures/program-activation/role")
    (unless (eq? first (activation)) (error "role initialized twice")))
  (let* ((attempt (lambda ()
                    (with-catch values
                      (lambda () (load-module "tao3k/yuanxu/t/fixtures/program-activation/failure")))))
         (first (attempt)))
    (unless (and (error? first) (eq? first (attempt)))
      (error "failed activation did not retain the same refusal")))
  (displayln "PROGRAM-LINK-AVAILABILITY-OK demand=ordered once=true failure=cached"))
