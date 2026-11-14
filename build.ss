#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/source this-source-file)
        (only-in :std/build-script defbuild-script)
        (only-in "./core-spec.ss" core-spec))

;; Install the loader and its libraries. Consumers select Module sources.
(defbuild-script core-spec)
