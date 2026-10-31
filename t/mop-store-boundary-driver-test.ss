;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native gxtest evaluates this facade; the tested body is the qualified AOT unit.
(import :std/test (only-in :gerbil/runtime/loader load-module))
;; gxtest evaluates source modules. Load the issued AOT unit explicitly rather
;; than allowing source evaluation to bypass its compiler-generated loader edge.
(extern namespace: yuanxu/t/mop-store-boundary-test
  mop-store-boundary-test test-cleanup!)
(load-module "yuanxu/t/mop-store-boundary-test")
(export mop-store-boundary-test test-cleanup!)
