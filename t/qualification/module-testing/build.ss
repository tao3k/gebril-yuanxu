#!/usr/bin/env -S gerbil interactive
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Copied into an isolated compiler Fixture's test-support directory.
(import :clan/poo/object
        (only-in :std/build-script defbuild-script)
        (only-in "../init.ss" yuanxu.init.exports))

;; Gerbil derives srcdir from the source anchor. The test package owns its
;; support spec at the init root even though this entry lives in a subdirectory.
(def tests (.get yuanxu.init.exports tests))
(defrule (this-source-file) (path-expand "init.ss" (.get tests source-root)))
(defbuild-script ((.get tests std-make-spec)) prefix: "yuanxu")
