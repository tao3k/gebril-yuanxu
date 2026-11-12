#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (for-syntax
          (only-in :std/source this-source-file)
          (only-in "./module-system/building/source-package.ss" register-module-build-source!)))
(begin-syntax
  (when (getenv "GERBIL_BUILD_VERBOSE" #f)
    (displayln "BUILD-BOOTSTRAP Core at=" (real-time)) (force-output))
  (register-module-build-source! (path-directory (this-source-file)) 'yuanxu))

(import (only-in :std/source this-source-file)
        (only-in :clan/poo/object .get)
        (only-in :std/build-script defbuild-script)
        (only-in "./init.ss" yuanxu.init.exports)
        (only-in "./core-spec.ss" core-spec))

;; Core libraries and selected Modules are ordinary native Make lists.
(defbuild-script
  (append (.get yuanxu.init.exports std-make-spec) core-spec))
