;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Trusted build-time declaration evaluation using the native expander. This
;;; neither compiles selected roots nor invokes their deferred core.link scopes.
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/expander current-expander-context make-top-context
                 current-expander-module-import eval-syntax)
        (only-in :clan/poo/object .o .ref)
        :core/module-system/source/admission
        :core/module-system/source/preparation
        :core/module-system/source/objects)
(export module-publication-reader)
(def (remove-reader-tree path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-reader-tree (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (reader-body forms)
  ;; Preparation owns these native compiler headers; preserve its prelude while
  ;; assigning a fresh private identity to this interpreter-only projection.
  (let loop ((tail forms) (prelude '()))
    (cond
     ((and (pair? tail) (eq? (car tail) 'prelude:))
      (loop (cddr tail) (list (car tail) (cadr tail))))
     ((and (pair? tail) (memq (car tail) '(package: namespace:)))
      (loop (cddr tail) prelude))
     (else (append prelude tail)))))
(def (module-publication-reader)
  (let ((guards '()) (refused? #f))
    (def (current!)
      (when refused? (error "build publication reader was refused"))
      (for-each (lambda (guard) (guard)) guards))
    (def (read-publication source-value)
      (with-catch
       (lambda (exception) (set! refused? #t) (raise exception))
       (lambda ()
         (current!)
         (let* ((prepared (poo-flow-prepare-module-publication source-value))
                (interface-path (poo-flow-module-source-ref-value source-value))
                (directory (make-temporary-file-name "publication-reader-"))
                (prefix (symbol->string (gensym 'publication-reader-)))
                (wrappers (make-hash-table))
                (artifacts (make-hash-table))
                (native-import (current-expander-module-import)))
           (def (write-wrapper path forms)
             (let* ((name (path-strip-extension (path-strip-directory path)))
                    (target (path-expand (string-append name ".ss") directory)))
               ;; Private identities avoid both native import-cache reuse and
               ;; global namespace collisions between immutable source sessions.
               (call-with-output-file target
                 (lambda (port)
                   (write 'package: port) (display " " port) (write prefix port) (newline port)
                   (write 'namespace: port) (display " " port)
                   (write (string-append prefix "/" name) port) (newline port)
                   (for-each (lambda (form) (write form port) (newline port)) forms)))
               (hash-put! artifacts (path-normalize target) #t)
               (hash-put! wrappers (path-normalize path) target)
               target))
           (dynamic-wind
            (lambda () (create-directory directory))
            (lambda ()
              (for-each
               (lambda (path)
                 (let (input (poo-flow-prepare-module-build-source path void))
                   (set! guards (cons (.ref input 'admit-current) guards))
                   ;; Keep native headers' prelude, replace only private identity.
                   (write-wrapper path (reader-body (.ref input 'compiler-forms)))))
               (.ref prepared 'role-sources))
              (set! guards (cons (.ref prepared 'admit-current) guards))
              (let* ((forms (.ref prepared 'compiler-forms))
                     (wrapper (write-wrapper interface-path (reader-body forms))))
                (parameterize
                    ((current-expander-context (make-top-context))
                     (current-expander-module-import
                      (lambda (path (reload? #f))
                        (let (target (hash-get wrappers (if (string? path) (path-normalize path) path)))
                          (when (and target (equal? target wrapper))
                            (error "publication bootstrap cannot import its own interface" interface-path))
                          ;; Local source imports must belong to the admitted role shell.
                          ;; External bootstrap libraries remain native imports.
                          (when (and (string? path) (not target)
                                     (string=? (path-extension path) ".ss")
                                     (not (hash-key? artifacts (path-normalize path))))
                            (error "publication bootstrap requires admitted roles or prebuilt imports" path))
                          (native-import (or target path) reload?)))))
                  (eval-syntax `(import ,wrapper))
                  (let (value (eval-syntax (.ref prepared 'binding)))
                    (current!)
                    value))))
            (lambda () (remove-reader-tree directory)))))))
    (.o read: read-publication admit-current: current!)))
