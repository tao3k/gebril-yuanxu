;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native gxtest evaluates this facade; the tested body is the qualified AOT unit.
(import (only-in :core/t/mop-store-boundary-test
                mop-store-boundary-test test-cleanup!))
(export mop-store-boundary-test test-cleanup!)
