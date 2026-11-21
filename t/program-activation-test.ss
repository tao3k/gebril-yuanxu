;;; SPDX-License-Identifier: Apache-2.0 OR LGPL-2.1-or-later
;;; Qualify the compiler-produced activation graph in an actual executable.
(import :gerbil/compiler :tao3k/yuanxu/module-system/building/program
        :std/encoding/json (only-in :std/misc/process run-process)
        (only-in :gerbil/runtime/loader add-load-path! load-path set-load-path!)
        :std/test (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/make pkg-config-libs))

(def (exercise-program-activation output)
  (def library (path-expand "lib" output))
  (create-directory* library)
  (add-load-path! library)
  (for-each
    (lambda (file)
      (compile-module (path-expand (string-append "t/fixtures/program-activation/" file ".ss"))
        [output-dir: library optimize: #t static: #t invoke-gsc: #t]))
    '("dependency" "role" "failure" "entry"))
  (yuanxu-project-compiled-program 'tao3k/yuanxu/t/fixtures/program-activation/entry output
    '(:tao3k/yuanxu/t/fixtures/program-activation/failure)
    gsc-options: ["-ld-options" (pkg-config-libs "openssl" "zlib" "sqlite3")])
  (def plan
    (parameterize ((current-json-read-options (make-JSONReadOptions object-as-hash: #t)))
      (call-with-input-file (path-expand "program.json" output) read-json)))
  (def modules (hash-ref plan "modules"))
  (def rows (if (vector? modules) (vector->list modules) modules))
  (def gsc (path-expand "bin/gsc" (gerbil-home)))
  (def (compile arguments) (run-process [gsc arguments ...]))
  (def objects '())
  (def inputs
    (map
      (lambda (row)
        (def scm (hash-ref row "scm"))
        (def base (path-strip-extension scm))
        (def c (string-append base ".c"))
        (def object (string-append base ".o"))
        (unless (hash-ref row "system")
          (set! base (path-expand (path-strip-directory base) output))
          (set! c (string-append base ".c"))
          (set! object (string-append base ".o"))
          (compile ["-c" "-o" c scm])
          (compile ["-obj" "-o" object c]))
        (set! objects (cons object objects))
        (list c (cons 'preload (not (hash-ref row "deferred" #f))))) rows))
  (def stub (hash-ref plan "stub"))
  (compile ["-c" stub])
  (compile ["-obj" (string-append (path-strip-extension stub) ".c")])
  (def link (path-expand "activation-link.c" output))
  (def expression
    (call-with-output-string
      (lambda (port)
        (write `(link-incremental ',(append inputs [(string-append (path-strip-extension stub) ".c")])
                                  output: ,link) port))))
  (compile ["-e" expression])
  (compile ["-obj" link])
  (def flags (hash-ref plan "link_options"))
  (def binary (path-expand "activation-control" output))
  (compile ["-exe" "-o" binary "-ld-options"
            (string-join (if (vector? flags) (vector->list flags) flags) " ")
            (reverse objects) ...
            (string-append (path-strip-extension stub) ".o")
            (string-append (path-strip-extension link) ".o")])
  ;; The generated library isn't on this child's path. A disk-dependent
  ;; activation hook would fail instead of silently loading a source carrier.
  (run-process [binary] stdout-redirection: #f
    environment: ["GERBIL_LOADPATH=" "GERBIL_PATH=/nonexistent"]))

(export program-activation-test)
(def program-activation-test
  (test-suite "Linked program activation"
    (test-case "link-only roles initialize on demand, in order, once, without source lookup"
      (call-with-temporary-directory "program-activation-"
        (lambda (directory)
          (def previous (load-path))
          (dynamic-wind void
            (lambda () (exercise-program-activation directory))
            (lambda () (set-load-path! previous))))))))
