prelude: :gerbil/core
;;; SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
;;; Inspect the admitted compiler inputs in a fresh Gerbil process.
(import :gerbil/compiler :gerbil/runtime/loader
        (only-in :gerbil/expander import-module current-expander-compiling? expander-context-id)
        (only-in :std/list/list append-map delete-duplicates/hash filter-map))
(extern namespace: gxc find-runtime-module-deps find-static-module-file)
(export yuanxu-observe-program-metadata)

(def (yuanxu-observe-program-metadata output imports inputs)
  (unless (and (string? output) (list? imports) (andmap symbol? imports)
               (list? inputs) (andmap string? inputs))
    (error "invalid program metadata observation"))
  ;; This child has no caller bindings. Consume the exact admitted paths of
  ;; its parent projection; never derive their order from process environment.
  (set-load-path! inputs)
  ;; Expand installed interfaces and their macro carriers, never initialize
  ;; ordinary runtime libraries merely to observe the link closure.
  (def contexts
    (parameterize ((current-expander-compiling? #t))
      (map import-module imports)))
  ;; An SSI may enroll compiled Yuanxu roles in begin-syntax. That registration
  ;; only runs in a fresh compiling context, never by activating its business
  ;; runtime. Retain their actual static compiler carriers as link inputs.
  (def static-rows
    (filter-map
      (lambda (context)
        (let (id (symbol->string (expander-context-id context)))
          (and (not (string-prefix? "gerbil/core" id))
               (list id (find-static-module-file context)))))
      (delete-duplicates/hash
        (append-map (lambda (context) (append (find-runtime-module-deps context) [context]))
                    contexts))))
  ;; Use the official loader's identities and dependency order. No Scheme
  ;; dependency parser or VM objects cross this build-time boundary.
  (let (modules
        (list-sort (lambda (a b) (< (module-load-order (car a))
                                    (module-load-order (car b))))
          (filter (lambda (entry)
                    (and (string? (cdr entry))
                         (not (member (car entry)
                           '("tao3k/yuanxu/module-system/building/program-metadata"
                             "tao3k/yuanxu/module-system/building/program-metadata~0")))))
                  (list-modules))))
    (call-with-output-file output
      (lambda (port)
        (write (append static-rows (map (lambda (entry)
                      (let (source (string-append (path-strip-extension (cdr entry)) ".scm"))
                        (unless (file-exists? source)
                          (error "missing compiler metadata carrier" (car entry) source))
                        (list (car entry) source))) modules)) port)))))
