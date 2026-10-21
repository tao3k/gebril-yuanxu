;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification driver: production selection/publishing, temporary sources.
(import :clan/poo/object
        (only-in :core/t/qualification/service-publication/fixtures ServicesFixture write-source)
        (only-in :core/module-system/source/link poo-flow-load-modules)
        (only-in :core/module-system/building/artifacts
          call-with-build-artifact-issuance run-build-artifact-process build-artifact-handoff)
        (only-in :std/io/tempfile call-with-temporary-directory)
        "./projection" (only-in "./store" store-add)
        (only-in :core/ops/progress call-with-execution-progress execution-progress!))
(def (main . _argv)
  (call-with-execution-progress 60000 600000
    (lambda (_frame)
      (def workspace (caddr (command-line)))
      (.call ServicesFixture .prepare (.o root: workspace))
      (execution-progress! 'publication-stages 1)
      (def owner (path-expand "modules/building/release" workspace))
      (write-source (path-expand "config.ss" owner)
        "(def Config (.o expression: \"release.nix\"))\n")
      (write-source (path-expand "objects.ss" owner)
        (string-append
          "(import (only-in :std/source this-source-file) (only-in :core/modules/nix/objects NixSource.) (only-in \"./config.ss\" Config))\n(export ReleaseSource)\n"
          "(.def (ReleaseSource @ NixSource.) expression: "
          "(path-expand (.get Config expression) (path-directory (this-source-file))))\n"))
      (write-source (path-expand "types.ss" owner)
        "(import (only-in :core/types poo-flow-predicate-contract))\n(export ScopeContract)\n(def ScopeContract (poo-flow-predicate-contract 'release/scope (lambda (v) (and (object? v) (.slot? v 'Source))) (lambda (_v _c) '())))\n")
      (write-source (path-expand "interface.ss" owner)
        "(.def Release identity: 'building/release core: (.o requires: (.o) build-publication: ReleaseSource scope-contract: ScopeContract exports: (.o Source: ReleaseSource)) features: (.o))\n")
      (write-source (path-expand "init.ss" workspace)
        "(poo-flow! mode: explicit (closed-package disable: #t) :services (postgresql) (gitea) (unused disable: #t) :applications (gitea-postgresql) :building (release))\n")
      (write-source (path-expand "probe.ss" workspace) "(export answer) (def answer 42)\n")
      ;; Declare generated package inputs before selecting the source directory.
      ;; Publication must not add directory members to an already observed epoch.
      (for-each (lambda (name) (write-source (path-expand name owner) "null\n"))
                '("release.nix" "release-name.nix" "omitted-release.nix"))
      (def selection (poo-flow-load-modules (path-expand "init.ss" workspace)))
      (.get selection build-graph)
      (execution-progress! 'publication-stages 2)
      (def package-name (cadr (call-with-input-file (path-expand "gerbil.pkg" workspace) read)))
      (def probe-name (string->symbol (string-append (symbol->string package-name) "/probe")))
      (def libdir (path-expand "lib" workspace))
      (def projection (probe-projection selection workspace probe-name))
      (def compile-main (probe-build workspace libdir))
      (call-with-build-artifact-issuance projection libdir (cut compile-main "compile"))
      (execution-progress! 'publication-stages 3)
      (def record-path (path-expand
        (find (cut string-prefix? ".poo-flow-build-issuance-" <>)
          (directory-files (list path: libdir ignore-hidden: #f))) libdir))
      (def transcript (run-build-artifact-process projection libdir
        (list "just" "build-publication-worker" workspace libdir (symbol->string probe-name) "persist" record-path)))
      (execution-progress! 'publication-stages 4)
      (def prefix "CORE-STORE-ROOT ")
      (def root-line (find (cut string-prefix? prefix <>) (string-split transcript #\newline)))
      (unless root-line (error "release publication did not complete"))
      (def packet-root (substring root-line (string-length prefix) (string-length root-line)))
      (def retained-packet (build-artifact-handoff (.get projection build-graph) libdir))
      (def omitted-observation (car (.get projection build-graph compiler-inputs)))
      (write-source (path-expand "release-name.nix" owner) "\"core-approved-publication\"\n")
      ;; The ordinary selected Module publishes Source. New processes discover its
      ;; Nix output from persistent policy; no release path is supplied on their CLI.
      (def (release-recipe packet-directory)
        (string-append "builtins.derivation { name = import ./release-name.nix; "
          "system = builtins.currentSystem; builder = \"/bin/sh\"; "
          "packet = " packet-directory "/issuance.ss; "
          "args = [ \"-c\" \"/bin/mkdir $out; /bin/cp $packet $out/issuance.ss\" ]; }\n"))
      (write-source (path-expand "release.nix" owner) (release-recipe packet-root))
      ;; Deliberately broken PUBLISHER output: valid store data and selected recipe,
      ;; but not enough observations to admit the actual selected Graph.
      (call-with-temporary-directory "core-omitted-publication"
        (lambda (directory)
          (def packet retained-packet)
          (def omitted omitted-observation)
          (def remaining
            (filter (lambda (row) (not (equal? (car row) (car omitted)))) (list-ref packet 2)))
          (unless (< (length remaining) (length (list-ref packet 2)))
            (error "omission control did not remove a real selected observation" omitted))
          (def incomplete
            (cons (car packet) (cons (cadr packet)
              (cons remaining (cdddr packet)))))
          (call-with-output-file (path-expand "issuance.ss" directory) (cut write incomplete <>))
          (write-source (path-expand "omitted-release.nix" owner) (release-recipe (store-add directory)))))
      (execution-progress! 'publication-stages 5)
      (displayln "APPROVED-SOURCE-PUBLISHED")
)))
