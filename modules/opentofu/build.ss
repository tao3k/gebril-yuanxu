;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Phase-isolated Build role for the single OpenTofu Module publication.
(import :clan/poo/object
        (only-in :std/encoding/json write-json)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :core/module-system/building/configuration-source poo-flow-core-configuration-source)
        (only-in :core/module-system/building/build-projection poo-flow-core-admit-build-inputs)
        ;; Build-tool native owners, not a second runtime facade or Loader.
        (only-in :core/modules/nix/types NixFlakeSourceContract)
        (only-in :core/types poo-flow-validation-evidence-accepted?)
        (only-in :core/modules/nix/func poo-flow-core-nix-source-inputs))
;; The native outer module slot keeps source/config refinements receiver-local.
(.def Build
  module: OpenTofuScope.
  kind: 'module/external-package identity: 'opentofu
  .prepare:
  (lambda (root context-current! publication)
    (unless (poo-flow-validation-evidence-accepted?
              (.call OpenTofuConfigContract .admit (.get module config) #f))
      (error "invalid OpenTofu upstream Config; expected a native Nix Source"))
    (unless (.get module config source)
      (error "build-required: OpenTofu Config.source must supply a Nix Source"))
    (let* ((source (.cc (.get module config source)))
           (flake? (poo-flow-validation-evidence-accepted?
                     (.call NixFlakeSourceContract .admit source #f)))
           (path (path-expand "config.ss" root))
           (configuration-input (poo-flow-core-configuration-source path 'Config context-current!
                                  role-sources: (.get publication role-sources)))
           (observed (append (.get configuration-input source-inputs) (.get source source-inputs)))
           (source-text (cdr (assoc path observed)))
           (source-digest (hex-encode (sha256 (string->utf8 source-text))))
           (projected-demand (.call module .build-inputs (.get configuration-input value)))
           (wire (call-with-output-string
                  (lambda (port)
                    (write-json port
                      (list->hash-table
                       (list (cons 'providers (list->vector (.get projected-demand providers)))
                             (cons 'configuration-source path)
                             (cons 'configuration-sha256 source-digest)
                             (cons 'binding "Config")
                             (cons 'source-inputs (poo-flow-core-nix-source-inputs observed)))))))))
      (def (current!)
        ((.get configuration-input admit-current))
        (poo-flow-core-admit-build-inputs observed))
      (current!)
      (.o identity: 'opentofu source-inputs: observed
          configuration: (.get configuration-input value) demand: projected-demand
          input-files: (list (cons "selection.json" wire))
          admit-current: current!
          .realize:
          (lambda (directory check-current!)
            (let* ((selection (path-expand "selection.json" directory))
                   (nix-source
                     (.cc source 'source-inputs observed
                       'arguments (.cc (.get source arguments) 'selection (if flake? wire selection))))
                   (publication (.call nix-source .prepare check-current!)))
              ;; Inherit Nix provenance/guards; specialize only domain values.
              (.+ publication
                (.o (:: @ [] artifact)
                    scope: (.cc module 'config
                              (.cc (.get module config) 'artifact artifact))
                    configuration: (.get configuration-input value)
                    ;; Value evidence over the immutable realized artifact is
                    ;; candidate-only. SelectedPackages checks package identity
                    ;; after ALL value validators, before publishing its result.
                    admission: (.call (.get scope types configuration) .admit configuration #f)))))))))
