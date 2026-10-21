;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; One compiler unit; service selection and admission use production Core.
(import :clan/poo/object :std/build-script
        (only-in :core/module-system/source/admission module-source-read)
        (only-in :core/module-system/building/artifacts current-build-output-directory))
(export probe-projection probe-build)
(def (probe-projection selection root identity)
  (def graph (.get selection build-graph))
  (def source (path-expand "probe.ss" root))
  (def original (module-source-read source))
  (.o build-graph: graph compiler-identities: (list identity)
      source-inputs: (append (.get graph compiler-inputs) (list (cons source original)))
      admit-current:
      (lambda ()
        ((.get graph compiler-current))
        (unless (equal? original (module-source-read source))
          (error "probe source changed")))))
(def (probe-build root lib)
  (let ((this-source-file (lambda () (path-expand "build.ss" root))))
    (defbuild-script '("probe") libdir: (or (current-build-output-directory) lib)
      bindir: (path-expand "bin" lib) parallelize: 1 optimize: #f)
    main))
