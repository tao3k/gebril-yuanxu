;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Compile changed Core libraries with the installed, unmodified compiler.
(import :gerbil/compiler :gerbil/compiler/compile
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/misc/ports read-all-as-u8vector))
(def output (path-expand (getenv "CORE_BUILD_PUBLICATION_LIB")))
(def observations '())
(def (digest source) (hex-encode (sha256 (call-with-input-file source read-all-as-u8vector))))
(for-each
  (lambda (source)
    (displayln "CORE-PUBLICATION-COMPILE " source)
    (force-output)
    (def before (digest source))
    (compile-module source
      [output-dir: output optimize: #t generate-ssxi: #t invoke-gsc: #t keep-scm: #t])
    (execute-pending-compile-jobs!)
    (unless (equal? before (digest source)) (error "Core source changed during compilation" source))
    (set! observations (cons (cons (path-expand source) before) observations)))
  '(;; Compile the CURRENT macro/prelude closure into this owned overlay too.
    ;; Never pair an old installed prelude .ssi with new declaration exports.
    "module-system/building/source-closure.ss"
    "module-system/source/role-forms.ss"
    "module-system/source/declaration.ss"
    "module-system/source/module-prelude.ss"
    "module-system/source/config-prelude.ss"
    "module-system/authoring/import-policy.ss"
    "poo-clos/types.ss"
    "object-family/read-projection.ss"
    "types.ss"
    "admission/source.ss"
    ;; Keep the CLOS runtime and its macro interface on the SAME source cut as
    ;; its carrier Types; installed factors may otherwise cache older protos.
    "poo-clos/funcs.ss"
    "poo-clos/objects.ss"
    "poo-clos/generic-evolution.ss"
    "poo-clos/classes.ss"
    "poo-clos/model.ss"
    "poo-clos/instance-state.ss"
    "poo-clos/evolution.ss"
    "poo-clos/method-combination.ss"
    "poo-clos/dispatch.ss"
    "poo-clos/lifecycle.ss"
    "poo-clos/reflection.ss"
    "poo-clos/load-form.ss"
    "poo-clos/mop.ss"
    "poo-clos/lambda-list.ss"
    "poo-clos/declaration-ir-core.ss"
    "poo-clos/class-declaration-ir.ss"
    "poo-clos/method-combination-declaration-ir.ss"
    "poo-clos/declaration-ir.ss"
    "poo-clos/method-bundle-syntax.ss"
    "poo-clos/generic-syntax.ss"
    "poo-clos/syntax.ss"
    "poo-clos/interface.ss"
    "module-system/source/interface.ss"
    "module-system/source/preparation.ss"
    "module-system/source/admission.ss"
    "module-system/source/build.ss"
    "module-system/building/artifacts.ss"
    "ops/progress.ss"
    "ops/func.ss"
    "modules/nix/func.ss"
    "modules/nix/build-publication.ss"
    "modules/nix/objects.ss"
    "admission/publication.ss"
    "module-system/source/reader.ss"
    "module-system/building/build-projection.ss"
    "module-system/building/interface.ss"
    "module-system/selection/init-syntax.ss"))
(call-with-output-file (list path: (path-expand "core-sources.sha256" (path-directory output)) truncate: #t)
  (lambda (port)
    (for-each (lambda (row)
      (display (cdr row) port) (display "  " port) (display (car row) port) (newline port))
      (reverse observations))))
