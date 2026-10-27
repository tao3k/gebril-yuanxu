#!/usr/bin/env -S gerbil interactive
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/script defbuild-script)
        (only-in "./init.ss" yuanxu-native-shared.init.exports))
 ;; Native spec discovery precedes Make; expose this package's authored
 ;; libraries through the Gerbil's ordinary source-path lookup for that phase.
(add-load-path! (path-directory (this-source-file)))
(def tests
  (.call (.get yuanxu-native-shared.init.exports tests) .for-files
    '("first-test.ss" "second-test.ss")))
(defbuild-script ((.get tests std-make-spec)))
