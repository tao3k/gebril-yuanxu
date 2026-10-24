;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit build-tool evaluation of an observed role, not a Module Loader.
(import (only-in :clan/poo/object .o .get)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-admit-current! call-with-module-source-read-cache
                 current-module-source-phase)
        (only-in :yuanxu/module-system/source/reader module-prepared-source-binding))
(export yuanxu-configuration-source)
(def (yuanxu-configuration-source path binding context-current! role-sources: (roles '()))
  (unless (and (symbol? binding) (eq? (module-source-type path) 'regular))
    (error "configuration source requires a regular role and native binding" path binding))
  ;; A single synchronous validation of this closure shares its context check.
  ;; A new POO receiver is allocated on EVERY independent currentness call.
  ;; Nothing is cached across role evaluation, file writes or external effects.
  (def phase (make-parameter #f))
  (def evaluated-inputs '())
  (def (context!)
    (if (phase) (.get (phase) checked) (context-current!)))
  ;; Preparing inert role/header observations has no native expansion or
  ;; initialization. Share this ONE source-only window, then close it before
  ;; module-prepared-source-binding performs the native import below.
  (let-values (((prepared related current!)
                (call-with-module-source-read-cache
                  (lambda ()
                    (let-values (((prepared related)
                                  (parameterize ((phase (.o checked: (context-current!))))
                                    (values
                                      (yuanxu-prepare-module-build-source path context!)
                                      (map (lambda (file) (yuanxu-prepare-module-build-source file context!))
                                        (filter (lambda (file) (and (not (equal? path file))
                                                    (not (member (path-strip-directory file) '("interface.ss" "build.ss"))))) roles))))))
                      (def (current! (site 'configuration-public))
                        (parameterize ((current-module-source-phase site))
                          (call-with-module-source-read-cache
                            (lambda ()
                              (parameterize ((phase (.o checked: (context-current!))))
                                (module-source-admit-current! evaluated-inputs)
                                ((.get prepared admit-current))
                                (for-each (lambda (input) ((.get input admit-current))) related))))))
                      ;; Only inert header/role observations precede this check.
                      ;; Reuse the preparation's bytes, then END this window
                      ;; before the reader can import/initialize bootstrap tools.
                      (current! 'configuration-pre-bootstrap)
                      (values prepared related current!))))))
    (let (effective (module-prepared-source-binding prepared binding related
                     source-inputs: (lambda (inputs) (set! evaluated-inputs inputs))))
      ;; The reader checks prepared/related inputs AFTER native evaluation.
      ;; Its remaining work only releases completed private expansion results
      ;; and deletes its private wrapper directory. No author code or Nix lies
      ;; between that return check and this inert source projection. Keep the
      ;; pre-bootstrap check above and every later public current! call fresh.
      ;; Compiler support is guarded by current!, not serialized into a provider
      ;; package's configuration input. Keep those two dependency roles distinct.
      (.o value: effective source-inputs: (append (.get prepared source-inputs) (foldr append '() (map (cut .get <> source-inputs) related)))
          admit-current: current!))))
