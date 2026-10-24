;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: declarative init selection and hygienic namespace bindings.
;;; Invariant: the common init.ss path lowers only to declarative module data.

(import (for-syntax (only-in :clan/poo/object .ref .slot?)))

(import (for-syntax
          (only-in :gerbil/expander current-expander-context core-context-top
                   module-context? expander-context-id)
          (only-in :yuanxu/module-system/source/init module-init-intent module-init-export-name)))
(import (only-in :clan/poo/object .ref .o .+)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/interface yuanxu-init-build)
        :yuanxu/module-system/selection/syntax
        (only-in :yuanxu/profile-composition/user-profile
                 yuanxuUserProfile
                 yuanxuUserProfileSet
                 yuanxuUserProfileExtend
                 yuanxuDefaultUserSettings
                 yuanxu-default-user-setting-keys))
(export yuanxu!)

;;; The short form is the normal user entry. The two explicit binding forms
;;; remain available for profile registries without importing the full UI
;;; doctor, presentation, sandbox, and runtime configuration facade.
(defsyntax (yuanxu! stx)
  (syntax-case stx (profile extends)
    ((ctx option value init-clause ...)
     (memq (syntax->datum (syntax option)) '(mode: source: :load-modules))
     ;; Normalize literal data only. One private getter is shared by all mounts;
     ;; expansion does not demand a Module scope or a test executor.
     (let* ((intent
             (module-init-intent
               (list (cons 'yuanxu! (cdr (syntax->datum stx)))) #f))
            (mounts
             (if (.slot? intent 'windows)
               (map (cut .ref <> 'mount) (.ref intent 'windows))
               '(#f)))
            (owner (core-context-top (current-expander-context) module-context?))
            (getter (genident 'init-modules-getter))
            (base-exports (genident 'init-exports))
            (exports-value-id (genident 'init-exports-value)))
       (unless owner
         (raise-syntax-error #f "init declaration requires a module context" stx))
       (def (namespace-slot mount)
         (with-syntax ((key (datum->syntax (syntax ctx) (or mount 'modules)))
                       (get getter))
           (if mount
             (syntax (key (.ref (get) 'key)))
             (syntax (key (get))))))
       (when (ormap (lambda (mount)
                      (memq mount '(tests std-make-spec admit-current))) mounts)
         (raise-syntax-error #f "mount conflicts with an init export" stx))
       (with-syntax
         ((exports-binding
            (datum->syntax (syntax ctx)
              (module-init-export-name (expander-context-id owner))))
          (exports-base base-exports)
          (exports-value exports-value-id)
          ((mount-slot ...) (map namespace-slot mounts))
          (module-source-getter getter))
         (syntax
           (begin
             ;; All projections close over this one init-owned selection.
             (defvalues (exports-base module-source-getter)
               (yuanxu-init-build
                 (this-source-file ctx)
                 '(yuanxu! option value init-clause ...)))
             (def exports-value (.+ exports-base (.o mount-slot ...)))
             (defsyntax exports-binding
               (identifier-rules ()
                 (id (identifier? #'id) exports-value)))
             (export exports-binding)
             ;; Native runtime modules have one result, not projection values.
             (void))))))
    ((_ profile-binding
        profile-set-binding
        (profile profile-name (extends base-profile))
        init-clause ...)
     (syntax
      (begin
        (def profile-binding
          (yuanxuUserProfileExtend
           'profile-name
           base-profile
           (yuanxu-modules! init-clause ...)))
        (def profile-set-binding
          (yuanxuUserProfileSet
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
          (yuanxuUserProfile
           'profile-name
           (yuanxu-modules! init-clause ...)
           (yuanxuDefaultUserSettings 'profile-name)
           yuanxu-default-user-setting-keys))
        (def profile-set-binding
          (yuanxuUserProfileSet
           'user
           'profile-name
           (list profile-binding))))))
    ((ctx init-clause ...)
     (with-syntax ((module-bundles-binding
                    (datum->syntax (syntax ctx)
                                   'yuanxu-user-module-bundles)))
       (syntax
        (begin
          (def module-bundles-binding
            (yuanxu-modules! init-clause ...))
          (export module-bundles-binding)))))))
