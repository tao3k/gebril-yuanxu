;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: admitted source collections for maintained, contributor,
;;; and user module trees. Selection declarations remain separate POO values.

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/list/list every)
        :yuanxu/module-system/loader/load-path
        :yuanxu/module-system/source/admission
        :yuanxu/module-system/source/objects)

(export yuanxu-module-source-collection-prototype
        make-yuanxu-module-source-collection
        yuanxu-module-source-collection?
        yuanxu-module-source-collection-identity
        yuanxu-module-source-collection-owner
        yuanxu-module-source-collection-source-root
        yuanxu-module-source-collection-modules-directory
        yuanxu-module-source-collection-modules-root
        yuanxu-module-source-collection-locate
        yuanxu-module-style-policy-prototype
        yuanxu-default-module-style-policy
        yuanxu-module-required-role-files
        yuanxu-module-allowed-entrypoint-roles
        yuanxu-module-source-collection-validate!
        yuanxu-module-source-collection-interfaces
        yuanxu-module-source-collection-role-entrypoints
        yuanxu-module-load-path-prototype
        make-yuanxu-module-load-path
        extend-yuanxu-module-load-path
        yuanxu-module-load-path?
        yuanxu-module-load-path-identity
        yuanxu-module-load-path-collections
        yuanxu-module-load-path-locate
        make-yuanxu-contribution-module-source
        make-yuanxu-contribution-root-module-source
        make-yuanxu-user-interface-module-source
        make-yuanxu-user-interface-module-load-path
)

(def (nonempty-string? value)
  (and (string? value) (> (string-length value) 0)))

(def (yuanxu-directory-module-source-collection? value)
  (and (yuanxu-module-source-collection? value)
       (every (lambda (slot) (.slot? value slot))
              '(owner source-root modules-directory style-policy excluded-directories))
       (symbol? (.ref value 'owner))
       (nonempty-string? (.ref value 'source-root))
       (nonempty-string? (.ref value 'modules-directory))
       (object? (.ref value 'style-policy))
       (.slot? (.ref value 'style-policy) 'validate)
       (procedure? (.ref (.ref value 'style-policy) 'validate))
       (list? (.ref value 'excluded-directories))
       (every module-source-name? (.ref value 'excluded-directories))
       (procedure? (.ref value 'locate))))

(def (yuanxu-module-source-collection-owner collection)
  (.ref collection 'owner))

(def (yuanxu-module-source-collection-source-root collection)
  (.ref collection 'source-root))

(def (yuanxu-module-source-collection-modules-directory collection)
  (.ref collection 'modules-directory))

(def (yuanxu-module-source-collection-modules-root collection)
  (let ((source-root
         (yuanxu-module-source-collection-source-root collection))
        (modules-directory
         (yuanxu-module-source-collection-modules-directory collection)))
    (if (string=? source-root ".")
      modules-directory
      (path-expand modules-directory source-root))))

(def (yuanxu-module-source-entrypoint collection module-key module-root
                                         entrypoint-role)
  (let* ((module-root (path-normalize module-root))
         (entrypoint
          (path-expand (string-append (symbol->string entrypoint-role) ".ss")
                       module-root)))
    (make-yuanxu-module-source-ref
     'local entrypoint
     (list (cons 'kind 'module-tree)
           (cons 'module-key module-key)
           (cons 'module-id (string->symbol
                            (string-append (symbol->string (car module-key)) "/"
                                           (symbol->string (cdr module-key)))))
           (cons 'source-collection
                 (yuanxu-module-source-collection-identity collection))
           (cons 'source-owner
                 (yuanxu-module-source-collection-owner collection))
           (cons 'module-layout 'yuanxu-module-v1)
           (cons 'required-roles yuanxu-module-required-role-files)
           (cons 'module-tree-root module-root)
           (cons 'entrypoint entrypoint)
           (cons 'entrypoint-role entrypoint-role)))))

;;; Categories stay in module identity. Directory collections use the
;;; flat <modules-root>/<module-name> repository convention.
(def (yuanxu-module-source-collection-default-locate collection module-key
                                                       entrypoint-roles)
  (unless (and (pair? module-key) (symbol? (car module-key)) (symbol? (cdr module-key))
               (module-source-name? (symbol->string (car module-key)))
               (module-source-name? (symbol->string (cdr module-key))))
    (error "invalid source collection module key" module-key))
  (let (module-name (cdr module-key))
    (if (eq? module-name
             (yuanxu-module-source-collection-identity collection))
      (yuanxu-module-source-collection-role-entrypoints
       collection 'interface)
      (let* ((module-root
              (path-expand
               (symbol->string module-name)
               (yuanxu-module-source-collection-modules-root collection))))
        (if (and (not (member (symbol->string module-name)
                             (.ref collection 'excluded-directories)))
                 (module-source-type module-root))
          (begin
            ((.ref (.ref collection 'style-policy) 'validate)
             (.ref collection 'style-policy) module-name module-root module-source-read)
            (map (lambda (entrypoint-role)
                 (yuanxu-module-source-entrypoint
                  collection module-key module-root entrypoint-role))
               entrypoint-roles))
          '())))))

(def (yuanxu-module-source-collection-directory-names collection)
  (let (modules-root
        (yuanxu-module-source-collection-modules-root collection))
    (if (file-exists? modules-root)
      (let (module-names
          (filter
           (lambda (name)
             (and (not (member name (.ref collection 'excluded-directories)))
                  (eq? (file-info-type
                   (file-info (path-expand name modules-root)))
                  'directory)))
           (list-sort string<? (directory-files modules-root))))
        module-names)
      '())))

(def (yuanxu-module-source-collection-validate-directory-names!
      collection module-names)
  (let (modules-root
        (yuanxu-module-source-collection-modules-root collection))
    (for-each
     (lambda (module-name)
       (let ((module-root (path-expand module-name modules-root)))
         ((.ref (.ref collection 'style-policy) 'validate)
          (.ref collection 'style-policy) module-name module-root module-source-read)))
     module-names))
  collection)

(def (yuanxu-module-entrypoint-role-valid! entrypoint-role)
  (unless (memq entrypoint-role yuanxu-module-allowed-entrypoint-roles)
    (error "YUANXU-MODULE-E002 unsupported module entrypoint role"
           entrypoint-role yuanxu-module-allowed-entrypoint-roles))
  entrypoint-role)

(def (yuanxu-module-source-collection-validate! collection)
  (yuanxu-module-source-collection-validate-directory-names!
   collection
   (yuanxu-module-source-collection-directory-names collection)))

(def (yuanxu-module-source-collection-role-entrypoints collection
                                                         entrypoint-role)
  (unless (yuanxu-directory-module-source-collection? collection)
    (error "YUANXU-MODULE-E003 invalid module source collection" collection))
  (yuanxu-module-entrypoint-role-valid! entrypoint-role)
  (let* ((modules-root
          (yuanxu-module-source-collection-modules-root collection))
         (module-names
          (yuanxu-module-source-collection-directory-names collection)))
    (yuanxu-module-source-collection-validate-directory-names!
     collection module-names)
    (map
     (lambda (name)
       (let* ((module-root (path-expand name modules-root))
              (entrypoint
               (path-expand (string-append (symbol->string entrypoint-role) ".ss")
                            module-root)))
         (unless (file-exists? entrypoint)
           (error "YUANXU-MODULE-E004 requested optional role is absent"
                  name entrypoint-role))
         (yuanxu-module-source-entrypoint
          collection
          (cons 'custom (string->symbol name))
          module-root
          entrypoint-role)))
     module-names)))

(def (make-yuanxu-module-source-collection identity-value owner-value
                                              source-root-value
                                              modules-directory-value
                                              style-policy: (style-policy-value yuanxu-default-module-style-policy))
  (let (collection
        (.o (:: @ yuanxu-module-source-collection-prototype)
            (identity identity-value)
            (owner owner-value)
            (source-root source-root-value)
            (modules-directory modules-directory-value)
            (style-policy style-policy-value)
            (excluded-directories '())
            (locate yuanxu-module-source-collection-default-locate)))
    (unless (yuanxu-directory-module-source-collection? collection)
      (error "invalid Yuanxu module source collection" collection))
    collection))

;;; Repository paths are explicit inputs; no contributor registry is consulted.
(def (make-yuanxu-contribution-module-source identity-value source-root-value
                                               style-policy: (style-policy-value yuanxu-default-module-style-policy))
  (make-yuanxu-module-source-collection
   identity-value 'contributor source-root-value "modules"
   style-policy: style-policy-value))

;;; A contribution root is an on-demand projection over checked-out package
;;; directories.  The selected module identity chooses packages/<identity>;
;;; no contributor name, URL, or revision is registered in Scheme.
(def (yuanxu-contribution-root-locate collection module-key entrypoint-roles)
  (let* ((identity (cdr module-key))
         (source-root
          (path-expand
           (symbol->string identity)
           (yuanxu-module-source-collection-source-root collection)))
         (contribution
          (make-yuanxu-contribution-module-source
           identity source-root style-policy: (.ref collection 'style-policy))))
    (if (file-exists?
         (yuanxu-module-source-collection-modules-root contribution))
      ;; std/list/list append-map reverses each produced list.  Entrypoint order
      ;; is part of the loader contract, so flatten the bounded role projection
      ;; with native map/apply/append and preserve both role and module order.
      (apply append
             (map (lambda (entrypoint-role)
                    (yuanxu-module-source-collection-role-entrypoints
                     contribution entrypoint-role))
                  entrypoint-roles))
      '())))

(def (make-yuanxu-contribution-root-module-source identity-value
                                                     source-root-value
                                                     style-policy: (style-policy-value yuanxu-default-module-style-policy))
  (.o (:: @ yuanxu-module-source-collection-prototype)
      (identity identity-value)
      (owner 'contributor)
      (source-root source-root-value)
      (modules-directory ".")
      (style-policy style-policy-value)
      (locate yuanxu-contribution-root-locate)))

(def (make-yuanxu-user-interface-module-source identity-value
                                                  user-interface-root-value
                                                  style-policy: (style-policy-value yuanxu-default-module-style-policy))
  (make-yuanxu-module-source-collection
   identity-value 'user user-interface-root-value "modules"
   style-policy: style-policy-value))

(def (make-yuanxu-user-interface-module-load-path identity-value
                                                     user-interface-root-value
                                                     base-load-path)
  (make-yuanxu-module-load-path
   identity-value
   (cons
    (make-yuanxu-user-interface-module-source
     identity-value user-interface-root-value)
    (yuanxu-module-load-path-collections base-load-path))))


(def (yuanxu-module-source-collection-interfaces collection)
  (yuanxu-module-source-collection-role-entrypoints collection 'interface))
