#!/usr/bin/env -S gerbil interactive
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build the existing init-owned qualification publication; never run Cases.
(import :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/script defbuild-script)
        (only-in "../../../init.ss" yuanxu.init.exports))

(def root (path-expand "../../.." (path-directory (this-source-file))))
;; Core's installed libraries must precede source fallback. Prepending this
;; root would rebuild production libraries as support and change the closure
;; compared with the native test process.
(def qualifications (.get yuanxu.init.exports tests qualification))
(def support (.get qualifications build))
;; Keep the exact producer reference visible when a consumer refuses recovery;
;; a successful compilation alone cannot prove matching source publication.
(displayln "QUALIFICATION-SUPPORT artifact=" (.get support output-directory)
  " native-targets=" (length (.get support spec)))

;; Core's init owns the selected source identities and admission guards. The
;; official build command owns Make, compilation and publication before tests.
(defbuild-script ((.get qualifications std-make-spec))
  srcdir: root prefix: "yuanxu")
