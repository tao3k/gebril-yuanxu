;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private version inputs over the existing reader and selected-package owners.
(import :clan/poo/object
        (only-in :std/source this-source-file)
        (only-in :std/io/tempfile make-temporary-file-name clear-temporary-file!)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/ops/selected-packages SelectedPackages.)
        (only-in :core/modules/nix/objects NixSource.)
        (only-in :core/module-system/source/admission module-source-read)
        (only-in :core/module-system/source/reader module-publication-reader)
        (only-in :core/module-system/source/directory module-directory-context))
(export Workspace prepare-aws-selection! realize-aws-selection write-aws-version!)
(.def Workspace
  .acquire: (lambda ()
              (let (root (make-temporary-file-name "aws-context-publication-"))
                (create-directory root) root))
  .release: clear-temporary-file!)
(def repository (path-expand "../../../.." (path-directory (this-source-file))))
(def (write-source path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (write-aws-version! project version)
  (unless (member version '("parent" "child")) (error "unknown AWS fixture version" version))
  (write-source (path-expand "version.nix" project)
    (call-with-output-string (cut write version <>))))
(def (prepare-aws-selection! root)
  (def project (path-expand "project" root))
  (def catalog (path-expand "providers.nix" project))
  (def version (path-expand "version.nix" project))
  (write-aws-version! project "parent")
  (write-source catalog
    (string-append "{ pkgs }: let versions = import "
      (call-with-output-string
        (cut write (path-expand "t/fixtures/opentofu/versioned-schemas.nix" repository) <>))
      " { inherit pkgs; }; in { aws = versions.${import ./version.nix}; }\n"))
  (write-source (path-expand "gerbil.pkg" project)
    "(package: qualification prelude: :core/module-system/source/module-prelude)\n")
  (def init (path-expand "init.ss" project))
  (write-source init
    (call-with-output-string
      (lambda (port)
        (write `(poo-flow! mode: explicit source: ,(path-expand "modules" repository)
                  (aws @ ,(path-expand "scenarios/aws" repository))
                  (opentofu @ ,(path-expand "modules/opentofu" repository))
                  (nix @ ,(path-expand "modules/nix" repository))
                  (ops @ ,(path-expand "ops" repository))
                  (funflow @ ,(path-expand "modules/funflow" repository))
                  (json-schema @ ,(path-expand "modules/json-schema" repository))) port))))
  (.cc (.o) 'project project 'init init 'reader (module-publication-reader)))
(def (realize-aws-selection fixture directory (phase void))
  (def init (.get fixture init))
  ;; Existing source-context customization hook, as used by the selected-Graph
  ;; controls. Configure the actual publication, never replace its declaration.
  (def project (path-directory init))
  (def catalog-path (path-expand "providers.nix" project))
  (def version-path (path-expand "version.nix" project))
  (def expression-path (path-expand "modules/opentofu/nix/selected-provider-artifacts.nix" repository))
  (def collector-path (path-expand "modules/opentofu/nix/provider-artifacts.nix" repository))
  (.def (Source @ NixSource.)
    expression: expression-path
    arguments: (.o catalog: catalog-path collector: collector-path)
    source-inputs: (map (lambda (path) (cons path (module-source-read path)))
                       (list expression-path collector-path catalog-path version-path)))
  ;; The fixture owns one unchanged source snapshot, not a new compiler world
  ;; per package version. Only the selected Nix input/Graph changes. The reader
  ;; continues to guard all source bytes; its scopes and admissions are not reused.
  (def reader (.get fixture reader))
  (def (configure scope)
    (.cc scope 'config (.cc (.get scope config) 'source Source)))
  (def (read-publication source)
    (def published (.call reader read source))
    (if (not (eq? (.get published identity) 'opentofu)) published
      (let (baseline (.get published core))
        (.cc published 'core
          (.o (:: @ baseline)
            link: (lambda (dependencies) (configure (.call baseline link dependencies)))
            configuration-build:
            (let (build (.get baseline configuration-build))
              (.cc build 'module (configure (.get build module)))))))))
  (def context (module-directory-context init read-publication))
  (phase 'source-context)
  (def selection
    (poo-flow-load-modules
      (.cc context 'publication-inputs (.get reader inputs)
        'current? (lambda (generation)
                    (.call reader admit-current)
                    (.call context current? generation)))))
  ;; Demand the same Graph that SelectedPackages consumes. This separates pure
  ;; source preparation from Nix effects without constructing another Graph.
  (.get selection build-graph)
  (phase 'build-graph)
  (def packages
    (.call (.cc SelectedPackages.
             selection: selection
             directory: directory)
      .run))
  (phase 'packages-realized)
  (def result (.call selection .with-packages packages))
  (phase 'scopes-linked)
  result)
