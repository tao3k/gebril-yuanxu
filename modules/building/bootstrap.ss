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
(export poo-flow-core-bootstrap-spec)
(def (poo-flow-core-bootstrap-spec core-root)
  (using (core-root :~ string?)
    (let* ((root (string-append (path-strip-trailing-directory-separator (path-expand core-root)) "/")) (seen (make-hash-table)) (rows '())
           (native-import (current-expander-module-import)))
      (def (source-for context)
        (let (id (expander-context-id context))
          (and (symbol? id)
               (let (text (symbol->string id))
                 (and (string-prefix? "core/" text)
                      (let (source (path-expand (string-append (substring text 5 (string-length text)) ".ss") root))
                        (and (file-exists? source) source)))))))
      (def (visit value)
        (cond
         ((module-import? value) (visit (module-import-source value)))
         ((module-export? value) (visit (module-export-context value)))
         ((import-set? value) (visit (import-set-source value)))
         ((module-context? value)
          (let (source (source-for value))
            (when (and source (not (hash-key? seen source)))
              (hash-put! seen source #t)
              (for-each visit (module-context-import value))
              (set! rows (cons `(gxc: ,(path-strip-extension (substring source (string-length root) (string-length source)))) rows)))))))
      (parameterize
          ((current-expander-context (make-top-context))
           (current-expander-module-import
            (lambda (path (reload? #f))
              (let* ((context (native-import path reload?)) (source (source-for context)))
                (if (and source (not (equal? (path-normalize source) (path-normalize (module-context-path context)))))
                  (native-import source reload?) context)))))
        (visit (core-import-module (path-expand "modules/building/build-projection.ss" root))))
      (reverse rows))))
