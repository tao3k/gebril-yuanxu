#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (for-syntax (only-in :std/source this-source-file)
                    (only-in "./module-system/building/source-package.ss"
                             register-module-build-source!)))
(begin-syntax
  (register-module-build-source! (path-directory (this-source-file)) 'core))

(import (only-in :std/build-script defbuild-script)
        (only-in :std/source this-source-file)
        (only-in :std/misc/process run-process)
        (only-in "./init.ss" init.build-spec init.build-run)
        (only-in "./module-system/building/artifacts.ss" current-build-output-directory)
        (only-in "./core-spec.ss" core-spec))

;; init owns Module projection; top-level core-spec.ss owns ordinary Core roots.
(def native-main
  (let ()
    (defbuild-script (init.build-spec core-spec) libdir: (current-build-output-directory))
    main))
(def (main . args)
  ;; The public prelude is a separate native package. It retains its module
  ;; header and tao3k/yuanxu identity; Core retained roots remain header-free.
  (when (or (null? args) (member (car args) '("compile" "clean")))
    (let (directory (path-expand "yuanxu" (path-directory (this-source-file))))
      (run-process (append '("gxi" "build.ss") args) directory: directory)))
  (init.build-run core-spec native-main args))
