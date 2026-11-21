;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; An actual package-owned entry; obtaining its export must not inspect files.
(import :tao3k/yuanxu/module-system/selection/init-syntax)
(yuanxu! :test-dir "./t" mode: explicit source: "./modules" :custom (guestbook -smoke))
