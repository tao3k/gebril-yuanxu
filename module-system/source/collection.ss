;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: admitted source collections for maintained, contributor,
;;; and user module trees. Selection declarations remain separate POO values.

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/list/list every)
        :core/module-system/loader/load-path
        :core/module-system/source/admission
        :core/module-system/source/objects)

(export poo-flow-module-source-collection-prototype
        make-poo-flow-module-source-collection
        poo-flow-module-source-collection?
        poo-flow-module-source-collection-identity
        poo-flow-module-source-collection-owner
        poo-flow-module-source-collection-source-root
        poo-flow-module-source-collection-modules-directory
        poo-flow-module-source-collection-modules-root
        poo-flow-module-source-collection-locate
        poo-flow-module-style-policy-prototype
        poo-flow-default-module-style-policy
        poo-flow-module-required-role-files
        poo-flow-module-allowed-entrypoint-roles
        poo-flow-module-source-collection-validate!
        poo-flow-module-source-collection-interfaces
        poo-flow-module-source-collection-role-entrypoints
        poo-flow-module-load-path-prototype
        make-poo-flow-module-load-path
        extend-poo-flow-module-load-path
        poo-flow-module-load-path?
        poo-flow-module-load-path-identity
        poo-flow-module-load-path-collections
        poo-flow-module-load-path-locate
        make-poo-flow-contribution-module-source
        make-poo-flow-contribution-root-module-source
        make-poo-flow-user-interface-module-source
        make-poo-flow-user-interface-module-load-path
)

(def (nonempty-string? value)
  (and (string? value) (> (string-length value) 0)))

(def (poo-flow-directory-module-source-collection? value)
  (and (poo-flow-module-source-collection? value)
       (every (lambda (slot) (.slot? value slot))
              '(owner source-root modules-directory style-policy))
       (symbol? (.ref value 'owner))
       (nonempty-string? (.ref value 'source-root))
       (nonempty-string? (.ref value 'modules-directory))
       (object? (.ref value 'style-policy))
       (.slot? (.ref value 'style-policy) 'validate)
       (procedure? (.ref (.ref value 'style-policy) 'validate))
       (procedure? (.ref value 'locate))))

(def (poo-flow-module-source-collection-owner collection)
  (.ref collection 'owner))

(def (poo-flow-module-source-collection-source-root collection)
  (.ref collection 'source-root))

(def (poo-flow-module-source-collection-modules-directory collection)
  (.ref collection 'modules-directory))

(def (poo-flow-module-source-collection-modules-root collection)
  (let ((source-root
         (poo-flow-module-source-collection-source-root collection))
        (modules-directory
         (poo-flow-module-source-collection-modules-directory collection)))
    (if (string=? source-root ".")
      modules-directory
      (path-expand modules-directory source-root))))

(def (poo-flow-module-source-entrypoint collection module-key module-root
                                         entrypoint-role)
  (let (entrypoint
        (path-expand (string-append (symbol->string entrypoint-role) ".ss")
                     module-root))
    (make-poo-flow-module-source-ref
     'local entrypoint
     (list (cons 'kind 'module-tree)
           (cons 'module-key module-key)
           (cons 'module-id (string->symbol
                            (string-append (symbol->string (car module-key)) "/"
                                           (symbol->string (cdr module-key)))))
           (cons 'source-collection
                 (poo-flow-module-source-collection-identity collection))
           (cons 'source-owner
                 (poo-flow-module-source-collection-owner collection))
           (cons 'module-layout 'poo-flow-module-v1)
           (cons 'required-roles poo-flow-module-required-role-files)
           (cons 'module-tree-root module-root)
           (cons 'entrypoint entrypoint)
           (cons 'entrypoint-role entrypoint-role)))))

;;; Categories stay in module identity. Directory collections use the
;;; flat <modules-root>/<module-name> repository convention.
(def (poo-flow-module-source-collection-default-locate collection module-key
                                                       entrypoint-roles)
  (unless (and (pair? module-key) (symbol? (car module-key)) (symbol? (cdr module-key))
               (module-source-name? (symbol->string (car module-key)))
               (module-source-name? (symbol->string (cdr module-key))))
    (error "invalid source collection module key" module-key))
  (let (module-name (cdr module-key))
    (if (eq? module-name
             (poo-flow-module-source-collection-identity collection))
      (poo-flow-module-source-collection-role-entrypoints
       collection 'interface)
      (let* ((module-root
              (path-expand
               (symbol->string module-name)
               (poo-flow-module-source-collection-modules-root collection))))
        (if (module-source-type module-root)
          (begin
            ((.ref (.ref collection 'style-policy) 'validate)
             (.ref collection 'style-policy) module-name module-root module-source-read)
            (map (lambda (entrypoint-role)
                 (poo-flow-module-source-entrypoint
                  collection module-key module-root entrypoint-role))
               entrypoint-roles))
          '())))))

(def (poo-flow-module-source-collection-directory-names collection)
  (let (modules-root
        (poo-flow-module-source-collection-modules-root collection))
    (if (file-exists? modules-root)
      (let (module-names
          (filter
           (lambda (name)
             (eq? (file-info-type
                   (file-info (path-expand name modules-root)))
                  'directory))
           (list-sort string<? (directory-files modules-root))))
        module-names)
      '())))

(def (poo-flow-module-source-collection-validate-directory-names!
      collection module-names)
  (let (modules-root
        (poo-flow-module-source-collection-modules-root collection))
    (for-each
     (lambda (module-name)
       (let ((module-root (path-expand module-name modules-root)))
         ((.ref (.ref collection 'style-policy) 'validate)
          (.ref collection 'style-policy) module-name module-root module-source-read)))
     module-names))
  collection)

(def (poo-flow-module-entrypoint-role-valid! entrypoint-role)
  (unless (memq entrypoint-role poo-flow-module-allowed-entrypoint-roles)
    (error "POO-FLOW-MODULE-E002 unsupported module entrypoint role"
           entrypoint-role poo-flow-module-allowed-entrypoint-roles))
  entrypoint-role)

(def (poo-flow-module-source-collection-validate! collection)
  (poo-flow-module-source-collection-validate-directory-names!
   collection
   (poo-flow-module-source-collection-directory-names collection)))

(def (poo-flow-module-source-collection-role-entrypoints collection
                                                         entrypoint-role)
  (unless (poo-flow-directory-module-source-collection? collection)
    (error "POO-FLOW-MODULE-E003 invalid module source collection" collection))
  (poo-flow-module-entrypoint-role-valid! entrypoint-role)
  (let* ((modules-root
          (poo-flow-module-source-collection-modules-root collection))
         (module-names
          (poo-flow-module-source-collection-directory-names collection)))
    (poo-flow-module-source-collection-validate-directory-names!
     collection module-names)
    (map
     (lambda (name)
       (let* ((module-root (path-expand name modules-root))
              (entrypoint
               (path-expand (string-append (symbol->string entrypoint-role) ".ss")
                            module-root)))
         (unless (file-exists? entrypoint)
           (error "POO-FLOW-MODULE-E004 requested optional role is absent"
                  name entrypoint-role))
         (poo-flow-module-source-entrypoint
          collection
          (cons 'custom (string->symbol name))
          module-root
          entrypoint-role)))
     module-names)))

(def (make-poo-flow-module-source-collection identity-value owner-value
                                              source-root-value
                                              modules-directory-value
                                              style-policy: (style-policy-value poo-flow-default-module-style-policy))
  (let (collection
        (.o (:: @ poo-flow-module-source-collection-prototype)
            (identity identity-value)
            (owner owner-value)
            (source-root source-root-value)
            (modules-directory modules-directory-value)
            (style-policy style-policy-value)
            (locate poo-flow-module-source-collection-default-locate)))
    (unless (poo-flow-directory-module-source-collection? collection)
      (error "invalid POO Flow module source collection" collection))
    collection))

;;; Repository paths are explicit inputs; no contributor registry is consulted.
(def (make-poo-flow-contribution-module-source identity-value source-root-value
                                               style-policy: (style-policy-value poo-flow-default-module-style-policy))
  (make-poo-flow-module-source-collection
   identity-value 'contributor source-root-value "modules"
   style-policy: style-policy-value))

;;; A contribution root is an on-demand projection over checked-out package
;;; directories.  The selected module identity chooses packages/<identity>;
;;; no contributor name, URL, or revision is registered in Scheme.
(def (poo-flow-contribution-root-locate collection module-key entrypoint-roles)
  (let* ((identity (cdr module-key))
         (source-root
          (path-expand
           (symbol->string identity)
           (poo-flow-module-source-collection-source-root collection)))
         (contribution
          (make-poo-flow-contribution-module-source
           identity source-root style-policy: (.ref collection 'style-policy))))
    (if (file-exists?
         (poo-flow-module-source-collection-modules-root contribution))
      ;; std/list/list append-map reverses each produced list.  Entrypoint order
      ;; is part of the loader contract, so flatten the bounded role projection
      ;; with native map/apply/append and preserve both role and module order.
      (apply append
             (map (lambda (entrypoint-role)
                    (poo-flow-module-source-collection-role-entrypoints
                     contribution entrypoint-role))
                  entrypoint-roles))
      '())))

(def (make-poo-flow-contribution-root-module-source identity-value
                                                     source-root-value
                                                     style-policy: (style-policy-value poo-flow-default-module-style-policy))
  (.o (:: @ poo-flow-module-source-collection-prototype)
      (identity identity-value)
      (owner 'contributor)
      (source-root source-root-value)
      (modules-directory ".")
      (style-policy style-policy-value)
      (locate poo-flow-contribution-root-locate)))

(def (make-poo-flow-user-interface-module-source identity-value
                                                  user-interface-root-value
                                                  style-policy: (style-policy-value poo-flow-default-module-style-policy))
  (make-poo-flow-module-source-collection
   identity-value 'user user-interface-root-value "modules"
   style-policy: style-policy-value))

(def (make-poo-flow-user-interface-module-load-path identity-value
                                                     user-interface-root-value
                                                     base-load-path)
  (make-poo-flow-module-load-path
   identity-value
   (cons
    (make-poo-flow-user-interface-module-source
     identity-value user-interface-root-value)
    (poo-flow-module-load-path-collections base-load-path))))


(def (poo-flow-module-source-collection-interfaces collection)
  (poo-flow-module-source-collection-role-entrypoints collection 'interface))
