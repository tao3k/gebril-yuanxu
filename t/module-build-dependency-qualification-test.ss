;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compile only the observed public dependency closure, never Core targets.
(import :std/test
        (only-in :std/make make)
        (only-in :gerbil/expander core-import-module expander-context-id module-context-path)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module))
(export module-build-dependency-qualification-test)

(def module-build-dependency-qualification-test
  (if (getenv "CORE_QUALIFICATION_ROOT" #f)
    (test-suite "Public build dependency prerequisite"
      (test-case "only observed gerbil-poo units enter the isolated dependency cache"
        (def root-context (core-import-module ':yuanxu/module-system/building/build-projection))
        (def object-context (core-import-module ':clan/poo/object))
        (def source-root (path-directory (module-context-path object-context)))
        (def names '())
        (for-each-build-module root-context
          (lambda (context)
            (let (id (expander-context-id context))
              (when (and (symbol? id) (string-prefix? "clan/poo/" (symbol->string id)))
                (let* ((text (symbol->string id))
                       (name (substring text 9 (string-length text))))
                  (unless (member name names) (set! names (cons name names))))))))
        (check-equal? (> (length names) 0) #t)
        (displayln "QUALIFY public-dependency-only " (length names))
        (make (reverse names) srcdir: source-root
              libdir: (path-expand "lib" (getenv "GERBIL_PATH"))
              bindir: (path-expand "bin" (getenv "GERBIL_PATH"))
              prefix: "clan/poo" parallelize: 1 optimize: #f)
        (check-equal? (file-exists? (path-expand "lib/yuanxu" (getenv "GERBIL_PATH"))) #f)))
    (begin
      (displayln "SKIP public dependency qualification: CORE_QUALIFICATION_ROOT is unset")
      (test-suite "Source-only public dependencies (opt-in)" (void)))))
