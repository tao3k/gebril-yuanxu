;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; SDK-only source registration, before the build declaration imports Core.
(export register-module-build-source!)
(def (register-module-build-source! root expected-package)
  (let* ((directory (path-normalize root))
         (metadata (path-expand "gerbil.pkg" directory))
         (properties (call-with-input-file metadata read))
         (package (and (list? properties) (memq 'package: properties))))
    (unless (and package (pair? (cdr package))
                 (eq? (cadr package) expected-package))
      (error "build source package identity mismatch" metadata expected-package))
    ;; The SDK's package-prefix resolver confines this priority to this package.
    ;; Keep dependency lookup intact; never remove compiled artifacts.
    (add-load-path! directory)))
