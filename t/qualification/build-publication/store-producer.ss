;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Owns the ONLY original Core issuance. Exits before any recovery worker.
(import :clan/poo/object
        (only-in :yuanxu/t/qualification/service-publication/fixtures ServicesFixture write-source)
        (only-in :yuanxu/module-system/building/artifacts call-with-build-artifact-issuance
                 run-build-artifact-process)
        "./projection")
(export main)
;; Standard SDK launchers share this argument surface; issuance stays process-local.
(def (main producer-root)
(def services (.call ServicesFixture .prepare (.o root: producer-root)))
(def prefix (cadr (call-with-input-file (path-expand "gerbil.pkg" producer-root) read)))
(def probe-identity (string->symbol (string-append (symbol->string prefix) "/probe")))
(write-source (path-expand "probe.ss" producer-root) "(export answer) (def answer 42)\n")
(def projection (probe-projection (.get services selection) producer-root probe-identity))
(def lib (path-expand "lib" producer-root))
(def compile-main (probe-build producer-root lib))
(call-with-build-artifact-issuance projection lib (cut compile-main "compile"))
(def record (path-expand
  (find (cut string-prefix? ".yuanxu-build-issuance-" <>)
        (directory-files (list path: lib ignore-hidden: #f))) lib))
(display (run-build-artifact-process projection lib
  (list "just" "build-publication-worker" producer-root lib (symbol->string probe-identity) "persist" record))))
