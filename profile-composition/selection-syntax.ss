;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Hygienic bounded native scopes and indexed Core Module Profile selection.

(import (only-in :clan/poo/object .ref)
        (only-in :yuanxu/profile-composition/profile-bundle
                 yuanxu-select-module-profiles)
        (only-in :yuanxu/profile-composition/bindings yuanxu-module-scope)
        (for-syntax "scope-declaration.ss"))

(export use-module)

;;; A single compound body binds an existing scope; identifier-only tails
;;; retain the indexed ProfileBundle selection grammar.
;;; In the identifier-only branch, the default instance is the Module identity;
;;; `as` supplies a distinct instance identity. In a body it only binds an alias.
(defsyntax (use-module stx)
  (def bounded (bounded-module-use-parts stx #'use-module))
  (if bounded
    (with-syntax ((module-name (car bounded))
                  (alias (cadr bounded))
                  (body (caddr bounded)))
      (syntax/loc stx
        (let ((alias (yuanxu-module-scope module-name))) body)))
    (syntax-case stx ()
      ((_ module-name marker instance-name profile-name ...)
       (and (identifier? #'module-name)
            (identifier? #'marker)
            (eq? (syntax->datum #'marker) 'as)
            (identifier? #'instance-name)
            (pair? (syntax->list #'(profile-name ...)))
            (andmap identifier? (syntax->list #'(profile-name ...))))
       (syntax/loc stx
         (yuanxu-select-module-profiles
           module-name 'instance-name '(profile-name ...))))
      ((_ module-name marker rest ...)
       (and (identifier? #'marker) (eq? (syntax->datum #'marker) 'as))
       (raise-syntax-error #f
         "use-module as requires an alias and one compound body or named Profiles"
         stx))
      ((_ module-name profile-name ...)
       (and (identifier? #'module-name)
            (pair? (syntax->list #'(profile-name ...)))
            (andmap identifier? (syntax->list #'(profile-name ...))))
       (syntax/loc stx
         (yuanxu-select-module-profiles
           module-name (.ref module-name 'identity) '(profile-name ...))))
      (_
       (raise-syntax-error
         #f
         "use-module expects module [as instance] profile ... or module as alias (expression ...)"
         stx)))))
