#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (for-syntax
          (only-in :std/source this-source-file)
          (only-in "./module-system/building/source-package.ss" register-yuanxu-build-source!)))
(begin-syntax
  (when (getenv "GERBIL_BUILD_VERBOSE" #f)
    (displayln "BUILD-BOOTSTRAP Core at=" (real-time)) (force-output))
  (register-yuanxu-build-source! (path-directory (this-source-file))))

(import (only-in :clan/poo/object .get)
        (only-in "./prelude.ss")
        (only-in :std/build-script defbuild-script)
        (only-in "./init.ss" yuanxu.init.exports)
        (only-in "./module-system/building/artifacts.ss" current-build-output-directory)
        (only-in "./core-spec.ss" core-spec))

;; init owns Module projection; top-level core-spec.ss owns ordinary Core roots.
;; The SDK owns package compilation and its ordinary incremental outputs.
(def (package-main spec args)
  (let ()
    (defbuild-script spec libdir: (current-build-output-directory))
    (apply main args)))
;; Report actual dispatcher boundaries; completion still requires process exit.
(def (main . args)
  (when (getenv "GERBIL_BUILD_VERBOSE" #f)
    (displayln "BUILD-START Core " args " at=" (real-time)) (force-output))
  (begin0
    ((.get yuanxu.init.exports std-make-run) core-spec package-main args publication: #f)
    (when (getenv "GERBIL_BUILD_VERBOSE" #f)
      (displayln "BUILD-FINISH Core " args " at=" (real-time)) (force-output))))
