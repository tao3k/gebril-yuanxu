;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "./init.ss" yuanxu-package-consumer.init.exports))
(export selected-plan)
(def (selected-plan) (.get yuanxu-package-consumer.init.exports modules module-1 plan))
