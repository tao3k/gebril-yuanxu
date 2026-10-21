#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (for-syntax
          (only-in :std/source this-source-file)
          (only-in "./module-system/building/source-package.ss" register-yuanxu-build-source!)))
(begin-syntax
  (register-yuanxu-build-source! (path-directory (this-source-file))))

(import (only-in "./prelude.ss")
        (only-in :std/build-script defbuild-script)
        (only-in "./init.ss" init.build-spec init.build-run)
        (only-in "./module-system/building/artifacts.ss" current-build-output-directory)
        (only-in "./core-spec.ss" core-spec))

;; init owns Module projection; top-level core-spec.ss owns ordinary Core roots.
(def native-main
  (let ()
    (defbuild-script (init.build-spec core-spec) libdir: (current-build-output-directory))
    main))
(def (main . args)
  (init.build-run core-spec native-main args))
