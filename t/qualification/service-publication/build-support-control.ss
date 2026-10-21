;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Run the SAME existing assertion against baseline and candidate artifacts.
;;; Failure is recorded as failure; this is not a passing negative assertion.
(import (only-in :core/t/module-publication-test module-publication-test)
        (only-in :core/t/qualification/service-publication/selection selected-publication-suite))
(export build-support-control-test)
(def build-support-control-test
  (selected-publication-suite module-publication-test
    '("tool eligibility does not enlarge the declaration dependency closure")))
