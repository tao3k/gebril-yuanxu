;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Existing declaration binding; bounded adjacent-role discovery uses SDK file metadata.
(import (only-in "../bootstrap/body-inclusion.ss" include-module-body)
        (prefix-in (only-in :clan/poo/object
                            .def/ctx .o/ctx .o .ref) native-)
        (for-syntax :gerbil/expander
                    :yuanxu/module-system/source/role-forms))
(export .def include-module-body export-role-config define-module-build-binding
        current-module-build-phase? current-module-build-resolver)
(begin-syntax
  ;; Project only the direct native fields of a publication frame. Payloads
  ;; remain syntax; .def/ctx and .o/ctx own object semantics and slot binding.
  (def (publication-fields origin fields)
    (let loop ((tail (syntax->list fields)) (rows '()) (seen '()))
      (if (null? tail) (reverse rows)
        (let* ((field (car tail)) (value (syntax-e field)))
          (let-values (((name payload rest)
                        (if (keyword? value)
                          (begin
                            (unless (pair? (cdr tail))
                              (raise-syntax-error #f "missing publication field value" field))
                            (values (datum->syntax (stx-car origin) (string->symbol (keyword->string value)) (stx-source field))
                                    (cadr tail) (cddr tail)))
                          (syntax-case field ()
                            ((name payload) (identifier? #'name)
                             (values #'name #'payload (cdr tail)))
                            (_ (raise-syntax-error #f "publication frame expects direct native value slots" field))))))
            (when (memq (syntax-e name) seen)
              (raise-syntax-error #f "duplicate publication field" name))
            (with-syntax ((field-name name) (field-value payload))
              (loop rest (cons (syntax/loc field (field-name field-value)) rows) (cons (syntax-e name) seen))))))))
  (def (slot-row rows name)
    (let loop ((rows rows))
      (and (pair? rows)
           (if (eq? (syntax-e (stx-car (car rows))) name) (car rows) (loop (cdr rows))))))
  (def (slot-value rows name origin)
    (let (row (slot-row rows name))
      (unless row (raise-syntax-error #f "publication requires an explicit slot" origin name))
      (syntax-case row ()
        ((_ value) #'value)
        (_ (raise-syntax-error #f "publication field must be a direct native value slot" row)))))
  (def (object-parts value)
    (syntax-case value (native-.o)
      ((native-.o (:: options ...) body ...)
       (list #'(:: options ...) #'(body ...)))
      ((native-.o body ...) (list #'() #'(body ...)))
      (_ (raise-syntax-error #f "publication requires a literal native .o" value))))
  (def (dependency-aliases value)
    (let* ((parts (object-parts value))
           (rows (publication-fields value (cadr parts))))
      (unless (null? (syntax->datum (car parts)))
        (raise-syntax-error #f "publication requires explicit dependency aliases, without inherited aliases" value))
      (map (lambda (row)
             (syntax-case row ()
               ((name _value) #'name)
               (_ (raise-syntax-error #f "dependency alias must have a direct requirement value" row))))
           rows)))
  (def (lower-core value)
    (let* ((parts (object-parts value))
           (rows (publication-fields value (cadr parts)))
           (exports-row (slot-row rows 'exports))
           (exports-value (slot-value rows 'exports value))
           (aliases (dependency-aliases (slot-value rows 'requires value)))
           (dependencies (genident 'dependencies)))
      (slot-value rows 'scope-contract value)
      (when (slot-row rows 'link)
        (raise-syntax-error #f "declare core.exports once; core.link is generated" value))
      (with-syntax ((dependencies dependencies)
                    ((alias ...) aliases)
                    (exports-value exports-value))
        (let (link-row
              (syntax/loc exports-row
                (link (lambda (dependencies)
                        (let ((alias (native-.ref dependencies 'alias)) ...)
                          exports-value)))))
          (with-syntax ((context value) (options (car parts))
                        ((row ...) (map (lambda (row) (if (eq? row exports-row) link-row row)) rows)))
            #'(native-.o/ctx context options row ...)))))))

(defsyntax (.def stx)
  (syntax-case stx ()
    ((_ binding body ...)
     (let* ((location (stx-source stx))
            (file (and location (vector-ref location 0)))
            (role (and (string? file)
                       (string->symbol (path-strip-extension (path-strip-directory file))))))
       (and role (not (eq? role 'interface))
            (memq role yuanxu-module-allowed-entrypoint-roles)))
     (with-syntax ((context stx))
       #'(native-.def/ctx context binding body ...)))
    ((_ binding body ...)
     (let* ((rows (publication-fields stx #'(body ...)))
            (core-row (slot-row rows 'core))
            (core-value (lower-core (slot-value rows 'core stx)))
            (name (syntax-case #'binding ()
                    ((name _ ...) (identifier? #'name) #'name)
                    (name (identifier? #'name) #'name)
                    (_ (raise-syntax-error #f "expected a native .def binding" #'binding)))))
       (slot-value rows 'identity stx)
       (slot-value rows 'features stx)
       (with-syntax ((context stx) (name name)
                     ((build-binding ...)
                      (let* ((location (stx-source stx))
                             (file (and location (vector-ref location 0)))
                             (build-name (datum->syntax (stx-car stx) 'Build location)))
                        ;; Ordinary compilation reads the original interface,
                        ;; whereas the source reader supplies an admitted wrapper.
                        ;; Both routes need the SAME phase-checked lazy binding;
                        ;; never import build.ss into the runtime publication.
                        (if (and (string? file)
                                 (string=? (path-strip-directory file) "interface.ss")
                                 (module-regular-role-file? (path-expand "build.ss" (path-directory file)))
                                 (not (resolve-identifier build-name)))
                          (with-syntax ((build-name build-name))
                            (syntax->list #'((define-module-build-binding build-name))))
                          '())))
                     ((role-import ...)
                      (let* ((location (stx-source stx))
                             (file (and location (vector-ref location 0))))
                       (if (and (string? file) (string=? (path-strip-directory file) "interface.ss")
                                 ;; A prepared wrapper already imports prepared
                                 ;; roles. Following the include's original source
                                 ;; location would import bare config.ss a second time.
                                 (let (module (core-context-top (current-expander-context) module-context?))
                                   (and module (string? (module-context-path module))
                                        (equal? (path-normalize file)
                                                (path-normalize (module-context-path module))))))
                          (map (lambda (path)
                                 (datum->syntax (stx-car stx) `(import ,path) location))
                               (module-publication-role-imports (path-directory file)
                                                                module-regular-role-file?))
                          '())))
                     ((row ...) (map (lambda (row)
                                       (if (eq? row core-row)
                                         ;; Retain the caller's lexical slot binder and its token span.
                                         (syntax-case row ()
                                           ((field-name _)
                                            (with-syntax ((value core-value))
                                              (syntax/loc row (field-name value))))) row)) rows)))
         (syntax/loc stx
           (begin
             role-import ...
             build-binding ...
             (native-.def/ctx context binding row ...)
             (export name))))))
    (_ (raise-syntax-error #f "expected one native Module declaration" stx))))

;; Internal phase capability, not a runtime Loader or a global binding registry.
(def current-module-build-phase? (make-parameter #f))
(def current-module-build-resolver (make-parameter #f))
(def (module-build-binding-value state)
  ;; Check outside the cached slot: a previously forced Build is still forbidden
  ;; to ordinary config/runtime consumers.
  (unless (current-module-build-phase?)
    (error "Build is available only in the Module build-publication phase"))
  (native-.ref state 'value))
(defsyntax (define-module-build-binding stx)
  (syntax-case stx ()
    ((_ name)
     (identifier? #'name)
     (with-syntax ((resolver (genident 'build-resolver))
                   (state (genident 'build-state)))
       #'(begin
           (def resolver (current-module-build-resolver))
           (def state
             (native-.o value:
               (if resolver (resolver)
                   (error "Module Build has no admitted build resolver"))))
           (defsyntax name
             (identifier-rules ()
               ((_ . args) ((module-build-binding-value state) . args))
               (_ (module-build-binding-value state)))))))
    (_ (raise-syntax-error #f "expected an internal Build binding" stx))))

;; The native expander decides whether Config is visible after body expansion.
;; No second parser for Scheme definitions, and no export of private bindings.
(defsyntax (export-role-config stx)
  (syntax-case stx ()
    ((_ name)
     (identifier? #'name)
     (if (resolve-identifier #'name)
       (syntax/loc stx (export name))
       #'(begin)))
    (_ (raise-syntax-error #f "expected the internal Config export binding" stx))))
