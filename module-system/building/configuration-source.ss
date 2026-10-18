;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit build-tool evaluation of an observed role, not a Module Loader.
(import (only-in :clan/poo/object .o .get)
        (only-in :core/module-system/source/preparation poo-flow-prepare-module-build-source)
        (only-in :core/module-system/source/admission module-source-type call-with-module-source-read-cache)
        (only-in :core/module-system/source/reader module-prepared-source-binding))
(export poo-flow-core-configuration-source)
(def (poo-flow-core-configuration-source path binding context-current! role-sources: (roles '()))
  (unless (and (symbol? binding) (eq? (module-source-type path) 'regular))
    (error "configuration source requires a regular role and native binding" path binding))
  ;; A single synchronous validation of this closure shares its context check.
  ;; A new POO receiver is allocated on EVERY independent currentness call.
  ;; Nothing is cached across role evaluation, file writes or external effects.
  (def phase (make-parameter #f))
  (def (context!)
    (if (phase) (.get (phase) checked) (context-current!)))
  (let* ((prepared (poo-flow-prepare-module-build-source path context!))
         (related (map (lambda (file) (poo-flow-prepare-module-build-source file context!))
                    (filter (lambda (file) (and (not (equal? path file))
                                               (not (member (path-strip-directory file) '("interface.ss" "build.ss"))))) roles))))
    (def (current!)
      (call-with-module-source-read-cache
        (lambda ()
          (parameterize ((phase (.o checked: (context-current!))))
            ((.get prepared admit-current))
            (for-each (lambda (input) ((.get input admit-current))) related)))))
    (current!)
    (let (effective (module-prepared-source-binding prepared binding related))
      (current!)
      (.o value: effective source-inputs: (append (.get prepared source-inputs) (foldr append '() (map (cut .get <> source-inputs) related)))
          admit-current: current!))))
