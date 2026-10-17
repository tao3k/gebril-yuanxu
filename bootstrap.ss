#!/usr/bin/env gxi
;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/build-script :std/source "modules/building/bootstrap.ss")
;;; SDK + the declared gerbil-poo dependency suffice to discover this closure.
;;; Application publications are inputs to the resulting tool, never its roots.
(defbuild-script (poo-flow-core-bootstrap-spec (path-directory (this-source-file))))
