;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(import (only-in :gerbil/expander core-import-module core-bind-root-syntax!
                 expander-context-id core-library-package-plist))
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

(def (register-module-build-source! root expected-package prelude: (identity #f))
  (def library (package-source-path root expected-package))
  (when identity
    ;; Bind one verified native context, not an alias or another loader.
    (let* ((key (string->symbol (string-append ":" (symbol->string identity))))
           (metadata (core-library-package-plist library #t))
           (selected (memq 'prelude: metadata)))
      (unless (and selected (pair? (cdr selected)) (eq? (cadr selected) key))
        (error "build prelude does not match package language" library identity))
      (let (prelude (core-import-module (path-expand "prelude.ss" library)))
        (unless (eq? (expander-context-id prelude) identity)
          (error "build prelude identity mismatch" (expander-context-id prelude) identity))
        (core-bind-root-syntax! key prelude #t))))
  (add-load-path! library))

(def (register-yuanxu-build-source! root)
  (register-module-build-source! root 'yuanxu prelude: 'tao3k/yuanxu/prelude))
