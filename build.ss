#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/build-script defbuild-script)
        (only-in "./init.ss" init.build-spec)
        (only-in "./core-spec.ss" core-spec))

;; init owns Module projection; top-level core-spec.ss owns ordinary Core roots.
(defbuild-script (init.build-spec core-spec))
