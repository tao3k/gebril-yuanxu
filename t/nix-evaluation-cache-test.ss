;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Nix owns persistence. Traces distinguish evaluation from store availability.
(import :std/test :clan/poo/object
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :std/misc/process run-process)
        (only-in :std/misc/ports read-all-as-string)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/modules/nix/objects NixFlakeSource.
                 poo-flow-core-nix-flake-admit-generation))
(export nix-evaluation-cache-test)

(def (write-input path text)
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))

(def nix-evaluation-cache-test
  (test-suite "Nix-owned flake evaluation cache boundaries"
    (poo-flow-test-case "derived-path cache differs from eval and invalidates changed inputs"
      (call-with-temporary-directory "nix-evaluation-cache"
        (lambda (root)
          (def value (path-expand "value.nix" root))
          (write-input value "builtins.trace \"core-eval-cache-body\" \"before\"")
          (write-input (path-expand "flake.nix" root)
            (string-append
              "{ outputs = { self }: {\n"
              "  cached = import ./value.nix;\n"
              "  applied = args: import ./value.nix;\n"
              "  package = builtins.derivation {\n"
              "    name = \"core-eval-cache\"; system = \"aarch64-darwin\";\n"
              "    builder = \"/bin/sh\"; value = import ./value.nix;\n"
              "  };\n"
              "}; }\n"))
          (def (evaluate attribute (options '()))
            ;; Capture native trace and result together. No new runner, cache,
            ;; dependencies, realization or timing-based cache inference.
            (run-process
              (append
                (list "nix" "--extra-experimental-features" "nix-command flakes"
                      "eval" "--raw" "--no-update-lock-file"
                      (string-append "path:" (path-normalize root) "#" attribute))
                options)
              stdin-redirection: #f stderr-redirection: #t
              coprocess: read-all-as-string check-status: #t))
          (def (traced? text) (and (string-contains text "core-eval-cache-body") #t))
          (def cold (evaluate "cached"))
          (def warm (evaluate "cached"))
          (check-equal? (traced? cold) #t)
          ;; nix eval forces a Value rather than reading a cached scalar. Do not
          ;; infer an evaluation-cache hit merely from a pure flake reference.
          (check-equal? (traced? warm) #t)
          (check-equal? (and (string-contains warm "before") #t) #t)
          ;; Existing parameterized Flake Sources use --apply, which likewise
          ;; evaluates the function body in each fresh evaluator process.
          (check-equal? (traced? (evaluate "applied" '("--apply" "f: f {}"))) #t)
          (check-equal? (traced? (evaluate "applied" '("--apply" "f: f {}"))) #t)
          (check-equal? (traced? (evaluate "cached" '("--no-eval-cache"))) #t)
          (def (derivation (options '()))
            (run-process
              (append
                (list "nix" "--extra-experimental-features" "nix-command flakes"
                      "derivation" "show" "--no-update-lock-file"
                      (string-append "path:" (path-normalize root) "#package"))
                options)
              stdin-redirection: #f stderr-redirection: #t
              coprocess: read-all-as-string check-status: #t))
          (check-equal? (traced? (derivation)) #t)
          (check-equal? (traced? (derivation)) #f)
          (check-equal? (traced? (derivation '("--no-eval-cache"))) #t)
          (write-input value "builtins.trace \"core-eval-cache-body\" \"after\"")
          (def changed (evaluate "cached"))
          (check-equal? (traced? changed) #t)
          (check-equal? (and (string-contains changed "after") #t) #t)
          (check-equal? (traced? (derivation)) #t)
          (check-equal? (traced? (derivation)) #f))))
    (poo-flow-test-case "explicit path input overrides retain native cache and transitive invalidation"
      (call-with-temporary-directory "nix-selected-input"
        (lambda (root)
          (def input (path-expand "input" (path-normalize root)))
          (def publication (path-expand "publication" (path-normalize root)))
          (create-directory input)
          (create-directory publication)
          (write-input (path-expand "value.nix" input)
            "builtins.trace \"core-input-body\" \"before\"")
          (write-input (path-expand "flake.nix" publication)
            (string-append
              "{ inputs.selection = { url = \"path:" input "\"; flake = false; };\n"
              "outputs = { self, selection }: { package = builtins.derivation {\n"
              "name = \"selected-input\"; system = \"aarch64-darwin\"; builder = \"/bin/sh\";\n"
              "value = import (selection + \"/value.nix\"); }; }; }"))
          (def prefix '("nix" "--extra-experimental-features" "nix-command flakes"))
          (run-process (append prefix (list "flake" "lock" (string-append "path:" publication)))
            stdin-redirection: #f stderr-redirection: #f check-status: #t)
          (def lock (path-expand "flake.lock" publication))
          (def lock-before (call-with-input-file lock read-all-as-string))
          (def (query)
            (run-process
              (append prefix
                (list "path-info" "--derivation" "--no-update-lock-file"
                      "--override-input" "selection" (string-append "path:" input)
                      (string-append "path:" publication "#package")))
              stdin-redirection: #f stderr-redirection: #t
              coprocess: read-all-as-string check-status: #t))
          (def (traced? text) (and (string-contains text "core-input-body") #t))
          (check-equal? (traced? (query)) #t)
          (check-equal? (traced? (query)) #f)
          (.def (Source @ NixFlakeSource.)
            reference: (string-append "path:" publication)
            attribute: "package"
            inputs: (.o selection: input))
          (def expected (.call Source .instantiate))
          (check-equal? (.call Source .instantiate) expected)
          (def form (.call Source .guard-form expected))
          (check-equal? (car (reverse form)) (list 'quote (list (cons 'selection input))))
          (write-input (path-expand "value.nix" input)
            "builtins.trace \"core-input-body\" \"after\"")
          (check-exception
            (poo-flow-core-nix-flake-admit-generation
              (.get Source reference) "package" expected "nix"
              '() (.get Source source-inputs) (list (cons 'selection input)))
            error?)
          ;; The public guard has populated Nix's cache for the changed input.
          (check-equal? (traced? (query)) #f)
          (check-equal? (equal? expected (.call Source .instantiate)) #f)
          (write-input (path-expand "value.nix" input)
            "builtins.trace \"core-input-body\" \"third\"")
          (check-equal? (traced? (query)) #t)
          (check-equal? (traced? (query)) #f)
          (check-equal? (call-with-input-file lock read-all-as-string) lock-before)
          ;; An explicitly overridden data input does not authorize unrelated
          ;; implicit dependency updates. Only native Nix enforces this gate.
          (def flake (path-expand "flake.nix" publication))
          (def text (call-with-input-file flake read-all-as-string))
          (write-input flake
            (string-append
              "{ inputs.unexpected = { url = \"path:" input "\"; flake = false; };"
              (substring text 1 (string-length text))))
          (check-exception (query) error?)
          (check-equal? (call-with-input-file lock read-all-as-string) lock-before))))))
