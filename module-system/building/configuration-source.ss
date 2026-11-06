;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit build-tool evaluation of an observed role, not a Module Loader.
(import (runtime: :clan/poo/object)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-admit-current! call-with-module-source-read-cache
                 call-with-module-source-callback current-module-source-phase)
        (only-in :yuanxu/module-system/source/reader module-prepared-source-binding))
(export yuanxu-configuration-source)
(def (yuanxu-configuration-source path binding context-current! role-sources: (roles '()))
  (unless (and (symbol? binding) (eq? (module-source-type path) 'regular))
    (error "configuration source requires a regular role and runtime binding" path binding))
  (def evaluated-inputs '())
  ;; Configuration owns one context check per boundary. The role inputs carry
  ;; their own source checks; attaching the context callback to each input
  ;; would replay it on both sides of every role check.
  (def (admit-context!)
    (call-with-module-source-callback context-current!))
  (def (prepare!)
    (call-with-module-source-read-cache
      (lambda ()
        (values
          (yuanxu-prepare-module-build-source path void)
          (map (lambda (file) (yuanxu-prepare-module-build-source file void))
            (filter (lambda (file) (and (not (equal? path file))
                                        (not (member (path-strip-directory file) '("interface.ss" "build.ss")))))
              roles))))))
  (let-values (((prepared related) (prepare!)))
    (def (current! (phase 'configuration-public))
      (parameterize ((current-module-source-phase phase))
        (admit-context!)
        (call-with-module-source-read-cache
          (lambda ()
            (module-source-admit-current! evaluated-inputs)
            ((.get prepared admit-current))
            (for-each (lambda (input) ((.get input admit-current))) related)))))
    (current! 'configuration-pre-bootstrap)
    (let (effective (module-prepared-source-binding prepared binding related
                     context-current!: admit-context!
                     source-inputs: (lambda (inputs) (set! evaluated-inputs inputs))))
      ;; The reader checks prepared/related inputs AFTER runtime evaluation.
      ;; Its remaining work only releases completed private expansion results
      ;; and deletes its private wrapper directory. No author code or Nix lies
      ;; between that return check and this inert source projection. Keep the
      ;; pre-bootstrap check above and every later public current! call fresh.
      ;; Compiler support is guarded by current!, not serialized into a provider
      ;; package's configuration input. Keep those two dependency roles distinct.
      (.o value: effective source-inputs: (append (.get prepared source-inputs) (foldr append '() (map (cut .get <> source-inputs) related)))
          admit-current: current!))))
