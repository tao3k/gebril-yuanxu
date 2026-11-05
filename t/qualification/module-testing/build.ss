#!/usr/bin/env -S gerbil interactive
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Copied into an isolated compiler Fixture's test-support directory.
(import :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/script defbuild-script)
        (only-in "../init.ss" yuanxu.init.exports))

;; The selected init owns the test closure and signed publication. This is an
;; ordinary Gerbil build entry: it neither executes nor replaces the Harness.
(def root (path-expand ".." (path-directory (this-source-file))))
(def tests (.get yuanxu.init.exports tests))
(defbuild-script ((.get tests std-make-spec)) srcdir: root prefix: "yuanxu")
