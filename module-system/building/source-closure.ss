;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; This owner deliberately imports only the SDK. It can discover the Core
;;; build-tool closure before any application Module has been compiled.
(import (only-in :gerbil/expander core-import-module current-expander-context make-top-context
                 current-expander-module-import expander-context-id
                 module-context? module-context-import module-context-path
                 module-import? module-import-source module-export? module-export-context
                 import-set? import-set-source))
(export poo-flow-core-bootstrap-spec for-each-build-module poo-flow-core-bootstrap-contexts
        poo-flow-core-bootstrap-source-path)
(def (for-each-build-module root visit)
  (let (seen (make-hash-table-eq))
    (let walk ((value root))
      (cond
       ((module-import? value) (walk (module-import-source value)))
       ((module-export? value) (walk (module-export-context value)))
       ((import-set? value) (walk (import-set-source value)))
       ((and (module-context? value) (not (hash-key? seen value)))
        (hash-put! seen value #t)
        (for-each walk (module-context-import value))
        (visit value))))))
;; Closed Core tools: build projection and ordinary data construction. Published
;; Modules remain selected dependencies, never implicit bootstrap capabilities.
(def bootstrap-roots '(:core/module-system/building/build-projection
                      :core/module-system/building/configuration-source
                      ;; Public artifact/IR identity is shared with Core admission.
                      ;; These are library definitions, not a linked Module scope.
                      :core/modules/json-schema/json-schema-receipt
                      :core/configuration/json))
(def (poo-flow-core-bootstrap-contexts)
  (let (ids (make-hash-table))
    (for-each (lambda (root)
                (for-each-build-module (core-import-module root)
                  (lambda (context) (hash-put! ids (expander-context-id context) context))))
              bootstrap-roots)
    ids))
(def (poo-flow-core-bootstrap-source-path context core-root)
  ;; A caller supplies an already SDK-observed context and the trusted Core
  ;; source root. This is the same source projection used by bootstrap itself.
  (let (id (expander-context-id context))
    (and (symbol? id)
         (let (text (symbol->string id))
           (and (string-prefix? "core/" text)
                (let (source (path-expand (string-append (substring text 5 (string-length text)) ".ss") core-root))
                  (and (file-exists? source) source)))))))
(def (poo-flow-core-bootstrap-spec core-root)
  (using (core-root :~ string?)
    (let* ((root (string-append (path-strip-trailing-directory-separator (path-expand core-root)) "/")) (seen (make-hash-table)) (rows '())
           (native-import (current-expander-module-import)))
      (def (source-for context)
        (poo-flow-core-bootstrap-source-path context root))
      (def (visit context)
        (let (source (source-for context))
          (when (and source (not (hash-key? seen source)))
            (hash-put! seen source #t)
            (set! rows (cons `(gxc: ,(path-strip-extension (substring source (string-length root) (string-length source)))) rows)))))
      (parameterize
          ((current-expander-context (make-top-context))
           (current-expander-module-import
            (lambda (path (reload? #f))
              (let* ((context (native-import path reload?)) (source (source-for context)))
                (if (and source (not (equal? (path-normalize source) (path-normalize (module-context-path context)))))
                  (native-import source reload?) context)))))
        (for-each
          (lambda (identity)
            (let (name (symbol->string identity))
              (for-each-build-module
                (core-import-module (path-expand (string-append (substring name 6 (string-length name)) ".ss") root)) visit)))
          bootstrap-roots))
      (reverse rows))))
