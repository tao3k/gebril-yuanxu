;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: declarative init selection and hygienic namespace bindings.
;;; Invariant: the common init.ss path lowers only to declarative module data.

(import (for-syntax (only-in :clan/poo/object .ref .slot?)))

(import (for-syntax (only-in :core/module-system/source/init module-init-intent)))
(import (only-in :core/module-system/source/init module-init-intent)
        (only-in :clan/poo/object .ref)
        (only-in :std/source this-source-file)
        (only-in :core/module-system/building/interface poo-flow-core-init-build)
        :core/module-system/selection/syntax
        (only-in :core/profile-composition/user-profile
                 pooFlowUserProfile
                 pooFlowUserProfileSet
                 pooFlowUserProfileExtend
                 pooFlowDefaultUserSettings
                 poo-flow-default-user-setting-keys))
(export poo-flow!)

;; One hygienic projection rule for every mount; no generated getter catalogue.
(defrules define-init-namespace ()
  ((_ binding getter)
   (begin
     (defsyntax binding
       (identifier-rules ()
         (id (identifier? #'id)
             (getter))))
     (export binding)))
  ((_ binding getter mount)
   (begin
     (defsyntax binding
       (identifier-rules ()
         (id (identifier? #'id)
             (.ref (getter) 'mount))))
     (export binding))))

;;; The short form is the normal user entry. The two explicit binding forms
;;; remain available for profile registries without importing the full UI
;;; doctor, presentation, sandbox, and runtime configuration facade.
(defsyntax (poo-flow! stx)
  (syntax-case stx (profile extends)
    ((ctx option value init-clause ...)
     (memq (syntax->datum (syntax option)) '(mode: source: :load-modules))
     ;; Normalize literal data only. One private getter is shared by all mounts;
     ;; expansion does not demand a Module scope or a test executor.
     (let* ((intent
             (module-init-intent
               (list (cons 'poo-flow! (cdr (syntax->datum stx)))) #f))
            (mounts
             (if (.slot? intent 'windows)
               (map (cut .ref <> 'mount) (.ref intent 'windows))
               '(#f)))
            (getter (genident 'init-modules-getter)))
       ;; Public names use the declaration site's context. The accessor keeps
       ;; its fresh private identity, including through only-in and rename-in.
       (def (namespace-binding mount)
         (with-syntax
           ((binding
             (datum->syntax (syntax ctx)
               (string->symbol
                 (string-append "init."
                   (if mount (symbol->string mount) "modules")))))
            (get getter)
            (key (datum->syntax (syntax ctx) mount)))
           (if mount
             (syntax (define-init-namespace binding get key))
             (syntax (define-init-namespace binding get)))))
       (with-syntax
         ((init-binding (datum->syntax (syntax ctx) 'poo-flow-module-init))
          (build-spec-binding (datum->syntax (syntax ctx) 'init.build-spec))
          (build-current-binding (datum->syntax (syntax ctx) 'init.build-current!))
          (build-run-binding (datum->syntax (syntax ctx) 'init.build-run))
          (test-spec-binding (datum->syntax (syntax ctx) 'init.test-spec))
          (test-current-binding (datum->syntax (syntax ctx) 'init.test-current!))
          (test-source-binding (datum->syntax (syntax ctx) 'init.tests))
          ((namespace-definition ...) (map namespace-binding mounts))
          (module-source-getter getter))
         (syntax
           (begin
             (def init-binding
               (module-init-intent
                 '((poo-flow! option value init-clause ...)) #f))
             ;; All projections close over this one init-owned selection.
             (defvalues (build-spec-binding build-current-binding
                         test-spec-binding test-current-binding
                         test-source-binding module-source-getter build-run-binding)
               (poo-flow-core-init-build
                 (this-source-file ctx)
                 '(poo-flow! option value init-clause ...)))
             namespace-definition ...
             (export init-binding build-spec-binding build-current-binding build-run-binding
                     test-spec-binding test-current-binding test-source-binding)
             ;; A source module's native runtime promise has one result. Do not
             ;; leave defvalues' seven projection values as its last expression.
             (void))))))
    ((_ profile-binding
        profile-set-binding
        (profile profile-name (extends base-profile))
        init-clause ...)
     (syntax
      (begin
        (def profile-binding
          (pooFlowUserProfileExtend
           'profile-name
           base-profile
           (poo-flow-modules! init-clause ...)))
        (def profile-set-binding
          (pooFlowUserProfileSet
           'user
           'profile-name
           (list profile-binding))))))
    ((_ profile-binding
        profile-set-binding
        (profile profile-name)
        init-clause ...)
     (syntax
      (begin
        (def profile-binding
          (pooFlowUserProfile
           'profile-name
           (poo-flow-modules! init-clause ...)
           (pooFlowDefaultUserSettings 'profile-name)
           poo-flow-default-user-setting-keys))
        (def profile-set-binding
          (pooFlowUserProfileSet
           'user
           'profile-name
           (list profile-binding))))))
    ((ctx init-clause ...)
     (with-syntax ((module-bundles-binding
                    (datum->syntax (syntax ctx)
                                   'poo-flow-user-module-bundles)))
       (syntax
        (begin
          (def module-bundles-binding
            (poo-flow-modules! init-clause ...))
          (export module-bundles-binding)))))))
