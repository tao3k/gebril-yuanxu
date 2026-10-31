;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Gerbil-only role discovery shared by publication preparation and expansion.
(export yuanxu-module-allowed-entrypoint-roles module-publication-role-imports
        module-regular-role-file? module-init-export-name)

;; Native owner identity is metadata, not selection or object construction.
(def (module-init-export-name identity)
  (unless (symbol? identity) (error "init requires a native module identity" identity))
  (let (name (symbol->string identity))
    (let (separator (string-rindex name #\/))
      (string->symbol
        (string-append
          (if separator
            (string-append (substring name 0 separator) "."
                           (substring name (+ separator 1) (string-length name)))
            name)
          ".exports")))))
(def yuanxu-module-allowed-entrypoint-roles '(types objects func config interface build))
(def (module-publication-role-imports root present?)
  (filter-map
    (lambda (role)
      (and (memq role '(types func objects config))
           (let (name (string-append (symbol->string role) ".ss"))
             (and (present? (path-expand name root)) (string-append "./" name)))))
    yuanxu-module-allowed-entrypoint-roles))
(def (module-regular-role-file? path)
  (with-catch
    (lambda (e) (if (no-such-file-or-directory-exception? e) #f (raise e)))
    (lambda ()
      (unless (eq? (file-info-type (file-info path #f)) 'regular)
        (error "Module role is non-regular or a symlink" path))
      #t)))
