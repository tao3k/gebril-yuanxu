;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(import (only-in :gerbil/expander core-import-module core-bind-root-syntax!
                 expander-context-id))
(export register-module-build-source! register-yuanxu-build-source!)

(def (package-source-path root expected-package)
  (let* ((directory (path-normalize root))
         (metadata (path-expand "gerbil.pkg" directory))
         (properties (call-with-input-file metadata read))
         (package (and (list? properties) (memq 'package: properties))))
    (unless (and package (pair? (cdr package))
                 (eq? (cadr package) expected-package))
      (error "build source package identity mismatch" metadata expected-package))
    directory))

(def (register-module-build-source! root expected-package)
  (add-load-path! (package-source-path root expected-package)))

(def (register-yuanxu-build-source! root)
  ;; The root library package and this single file have distinct identities.
  ;; Bind the actual native module context, so the expander's bound-prelude
  ;; branch can resolve the language before a compiled copy is installed.
  (let* ((library (package-source-path root 'yuanxu))
         (prelude (core-import-module (path-expand "prelude.ss" library))))
    (unless (eq? (expander-context-id prelude) 'tao3k/yuanxu/prelude)
      (error "build prelude identity mismatch" (expander-context-id prelude)))
    (add-load-path! library)
    (core-bind-root-syntax! ':tao3k/yuanxu/prelude prelude #t)))
