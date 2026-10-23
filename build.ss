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
        (only-in "./module-system/building/script.ss" defbuild-script)
        (only-in "./init.ss" yuanxu.init.exports)
        (only-in "./module-system/building/artifacts.ss" current-build-output-directory)
        (only-in "./core-spec.ss" core-spec))

;; init.exports owns selected Module targets; core-spec owns library targets.
;; Only this entry consumes both. core-spec must never compile init itself.
;; The adapter keeps role/currentness boundaries inside the SDK consumer.
(def modules-spec (.get yuanxu.init.exports std-make-spec))
(defbuild-script (modules-spec core-spec) libdir: (current-build-output-directory))
