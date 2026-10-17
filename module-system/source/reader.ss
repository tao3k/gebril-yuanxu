;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Trusted build-time declaration evaluation using the native expander. This
;;; neither compiles selected roots nor invokes their deferred core.link scopes.
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/expander current-expander-context make-top-context
                 current-expander-module-import eval-syntax expander-context-id)
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
  (let ((guards '()) (dependencies (make-hash-table)) (refused? #f))
    (def (current!)
      (when refused? (error "build publication reader was refused"))
      (for-each (lambda (guard) (guard)) guards))
    (def (read-publication source-value)
      (with-catch
       (lambda (exception) (set! refused? #t) (raise exception))
       (lambda ()
         (current!)
         (let* ((prepared (poo-flow-prepare-module-publication source-value))
                (interface-path (path-normalize (poo-flow-module-source-ref-value source-value)))
                (root (path-directory interface-path))
                (id-text (symbol->string (.ref prepared 'compiler-identity)))
                (id-prefix (substring id-text 0 (- (string-length id-text) (string-length "interface"))))
                (directory (make-temporary-file-name "publication-reader-"))
                (prefix (symbol->string (gensym 'publication-reader-)))
                (wrappers (make-hash-table)) (artifacts (make-hash-table))
                (input-values '()) (native-import (current-expander-module-import)))
           (def (write-wrapper path forms)
             (let* ((name (string-append (number->string (hash-length wrappers)) "-" (path-strip-directory path)))
                    (target (path-expand name directory)))
               (call-with-output-file target
                 (lambda (port)
                   (write 'package: port) (display " " port) (write prefix port) (newline port)
                   (write 'namespace: port) (display " " port)
                   (write (string-append prefix "/" (path-strip-extension name)) port) (newline port)
                   (for-each (lambda (form) (write form port) (newline port)) forms)))
               (hash-put! artifacts (path-normalize target) #t)
               (hash-put! wrappers path target) target))
           (def (source-wrapper original-path)
             (let (path (path-normalize original-path))
               (when (equal? path interface-path)
                 (error "publication bootstrap cannot import its own interface" interface-path))
               (or (hash-get wrappers path)
                   (let (input (poo-flow-prepare-module-private-source root original-path void))
                     (set! guards (cons (.ref input 'admit-current) guards))
                     (set! input-values (cons input input-values))
                     (write-wrapper path (reader-body (.ref input 'compiler-forms)))))))
           (dynamic-wind
            (lambda () (create-directory directory))
            (lambda ()
              (for-each (lambda (path) (source-wrapper (path-normalize path))) (.ref prepared 'role-sources))
              (set! guards (cons (.ref prepared 'admit-current) guards))
              (let (wrapper (write-wrapper interface-path (reader-body (.ref prepared 'compiler-forms))))
                (parameterize
                    ((current-expander-context (make-top-context))
                     (current-expander-module-import
                      (lambda (path (reload? #f))
                        (cond
                         ((and (string? path) (hash-key? artifacts (path-normalize path)))
                          (native-import path reload?))
                         ((and (string? path) (string=? (path-extension path) ".ss"))
                          (native-import (source-wrapper path) reload?))
                         (else
                          (let* ((context (native-import path reload?))
                                 (identity (expander-context-id context))
                                 (id (and (symbol? identity) (symbol->string identity))))
                            ;; A preinstalled private .ssi must not hide current
                            ;; owner sources. Redirect it before module evaluation.
                            (if (and id (string-prefix? id-prefix id))
                              (native-import
                               (source-wrapper
                                (path-expand (string-append (substring id (string-length id-prefix) (string-length id)) ".ss") root)) reload?)
                              context)))))))
                  (eval-syntax `(import ,wrapper))
                  (let (value (eval-syntax (.ref prepared 'binding)))
                    (current!)
                    (let (roles (map path-normalize (.ref prepared 'role-sources)))
                      (hash-put! dependencies interface-path
                        (filter (lambda (input) (not (member (.ref input 'path) roles))) (reverse input-values))))
                    value))))
            (lambda () (remove-reader-tree directory)))))))
    (.o read: read-publication admit-current: current!
        inputs: (lambda (source)
                  (current!)
                  (hash-ref dependencies (path-normalize (poo-flow-module-source-ref-value source)))))))
