;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: declarative init selection and hygienic namespace bindings.
;;; Invariant: the common init.ss path lowers only to declarative module data.

(import (for-syntax
          (only-in :gerbil/expander current-expander-context core-context-top
                   module-context? expander-context-id)
          (only-in :yuanxu/module-system/source/role-forms module-init-mounts module-init-export-name)))
(import (only-in :clan/poo/object .ref .o .+)
        (only-in :std/source this-source-file)
        (only-in :yuanxu/module-system/building/interface yuanxu-init-build)
)
(export expand-yuanxu-declaration)

;;; Every named window uses the same module protocol. Profiles and Scenarios
;;; are namespace mounts, not alternate declaration or loading protocols.
(begin-syntax
  (def (expand-declaration stx)
  (syntax-case stx ()
    ((ctx option value init-clause ...)
     (memq (syntax->datum (syntax option)) '(mode: source: :load-modules))
     ;; Normalize literal data only. One private getter is shared by all mounts;
     ;; expansion does not demand a Module scope or a test executor.
     (let* ((mounts
             (module-init-mounts
               (list (cons 'yuanxu! (cdr (syntax->datum stx))))))
            (owner (core-context-top (current-expander-context) module-context?))
            (getter (genident 'init-modules-getter))
            (base-exports (genident 'init-exports))
            ;; An exported identifier transformer needs a stable private runtime
            ;; anchor across source expansion and separate native compilation.
            ;; Caller-context syntax gives this binding the same source ownership
            ;; as the qualified export; other temporary locals remain hygienic.
            (exports-value-id
              (datum->syntax (syntax ctx)
                (string->symbol
                  (string-append
                    (symbol->string (module-init-export-name (expander-context-id owner)))
                    "::value")))))
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
             ;; Runtime runtime modules have one result, not projection values.
             (void))))))
    (_ (raise-syntax-error #f
         "yuanxu! requires a module source/window declaration; use rename: for Profiles or Scenarios"
         stx)))))

(defsyntax (expand-yuanxu-declaration stx)
  (syntax-case stx ()
    ((_ original) (expand-declaration #'original))))
