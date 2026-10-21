;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :core/t/module-publication-test module-publication-test)
        (only-in :core/t/qualification/service-publication/selection selected-publication-suite))
(export reader-root-collection-test)
(def reader-root-collection-test
  (selected-publication-suite module-publication-test
    '("publication keeps unique original reads and refuses changed provenance"
      "reader warm inputs preserve the original graph without a weak projection claim")))
