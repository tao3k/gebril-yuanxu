;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Owns the ONLY original Core issuance. Exits before any recovery worker.
(import :clan/poo/object
        (only-in "../testing/directory.ss" write-source)
        (only-in "../service-publication/fixtures.ss" ServicesFixture)
        (only-in :yuanxu/module-system/building/artifacts call-with-build-artifact-issuance
                 run-build-artifact-process)
        (only-in :yuanxu/observability/testing-script TestingScript.)
        "./projection")
(export main)
;; Standard Gerbil launchers share this argument surface; issuance stays process-local.
(def (main producer-root (worker-command #f))
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
  (append (or worker-command '("gerbil")) (.get TestingScript. runtime-options)
    (if worker-command '("worker")
      '("interactive" "t/qualification/build-publication/worker.ss"))
    (list
          producer-root lib (symbol->string probe-identity) "persist" record)))))
