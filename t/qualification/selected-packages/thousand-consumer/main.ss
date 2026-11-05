;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in "./init.ss" yuanxu-thousand-consumer.init.exports))
(export selected-plan)
(def (selected-plan)
  (.get yuanxu-thousand-consumer.init.exports Corpus module-1 plan))
