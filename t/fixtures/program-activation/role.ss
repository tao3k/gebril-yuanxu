prelude: :gerbil/core
package: tao3k/yuanxu/t/fixtures/program-activation
;;; SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
(import "./dependency")
(export activation)
;; A fresh identity proves that the initializer was not executed twice.
(def activation (list answer))
