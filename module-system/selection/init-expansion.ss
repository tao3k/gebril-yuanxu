;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: declarative init selection and hygienic namespace bindings.
;;; Invariant: the common init.ss path lowers only to declarative module data.

(import (for-syntax
          (only-in :gerbil/expander current-expander-context core-context-top
                   module-context? expander-context-id module-context-path current-expander-compiling? stx-car datum->syntax
                   make-top-context current-expander-phi current-import-expander-phi
                   current-export-expander-phi current-expander-marks)
          (only-in :tao3k/yuanxu/module-system/source/role-forms module-init-mounts module-init-export-name)
          (only-in :gerbil/compiler/base module-id->path-string)
          (only-in :tao3k/yuanxu/module-system/source/deferred-declaration module-binding-action)))
(import (only-in :clan/poo/object .ref .o .+)
        (only-in :std/source this-source-file)
        (only-in :tao3k/yuanxu/module-system/building/interface yuanxu-init-build)
)
(export expand-yuanxu-declaration expand-yuanxu-program-declaration)

;;; Every named window uses the same module protocol. Profiles and Scenarios
;;; are namespace mounts, not alternate declaration or loading protocols.
(begin-syntax
  (def (expand-declaration stx (program #f) (origin #f))
  (syntax-case stx ()
    ((ctx option value init-clause ...)
     (memq (syntax->datum (syntax option)) '(mode: source: :load-modules :test-dir))
     ;; Normalize literal data only. One private getter is shared by all mounts;
     ;; expansion does not demand a Module scope or a test executor.
     (let* ((owner (core-context-top (current-expander-context) module-context?))
            (mounts
             (module-init-mounts
               (list (cons 'yuanxu! (cdr (syntax->datum stx))))
               (or (and origin (syntax->datum origin)) (and owner (module-context-path owner)))))
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
       (def (mount-binding mount)
         (let (name (datum->syntax (syntax ctx) mount))
           (with-syntax ((name name) (value exports-value-id))
             #'(begin
                 (defsyntax name
                   (identifier-rules ()
                     (id (identifier? #'id) (.ref value 'name))))
                 (export name)))))
       (when (ormap (lambda (mount)
                      (memq mount '(tests std-make-spec admit-current .project-build))) mounts)
         (raise-syntax-error #f "mount conflicts with an init export" stx))
       (with-syntax
         ((exports-binding
            (datum->syntax (syntax ctx)
              (module-init-export-name (expander-context-id owner))))
          (make-spec-binding (datum->syntax (syntax ctx) 'std-make-spec))
          (exports-base base-exports)
          (compiled-program (or program #'#f))
          (compiled-selection? (if program #'#t #'#f))
          (source-origin (or origin #'(this-source-file ctx)))
          (native-unit
            (datum->syntax (syntax ctx)
              (string->symbol
                (string-join (string-split (module-id->path-string (expander-context-id owner)) #\/) "__"))))
          (exports-value exports-value-id)
          ((mount-slot ...) (map namespace-slot mounts))
          ((mount-export ...) (map mount-binding (filter identity mounts)))
          (module-source-getter getter))
         (syntax
           (begin
             ;; All projections close over this one init-owned selection.
             (defvalues (exports-base module-source-getter)
               (yuanxu-init-build
                 source-origin
                 '(yuanxu! option value init-clause ...)
                 compiled-program 'native-unit compiled-selection?))
             (def exports-value (.+ exports-base (.o mount-slot ...)))
             (defsyntax exports-binding
               (identifier-rules ()
                 (id (identifier? #'id) exports-value)))
             ;; A build consumer imports its projection directly. Reuse the
             ;; same init-owned preparation; do not construct another Graph.
             (defsyntax make-spec-binding
               (identifier-rules ()
                 (id (identifier? #'id)
                     (.ref exports-value 'std-make-spec))))
             (export exports-binding make-spec-binding)
             mount-export ...
             ;; Runtime runtime modules have one result, not projection values.
             (void))))))
    (_ (raise-syntax-error #f
         "yuanxu! requires a module source/window declaration; use rename: for Profiles or Scenarios"
         stx)))))

(defsyntax (expand-yuanxu-declaration stx)
  (syntax-case stx ()
    ((_ original)
     (if (current-expander-compiling?)
       (let* ((owner (core-context-top (current-expander-context) module-context?))
              (path (and owner (module-context-path owner))))
         (unless (string? path) (raise-syntax-error #f "native init requires its source module" stx))
         (let skip-header
           ((forms
             (parameterize ((current-expander-context (make-top-context))
                            (current-expander-compiling? #f)
                            (current-expander-phi 0)
                            (current-import-expander-phi #f)
                            (current-export-expander-phi #f)
                            (current-expander-marks '()))
               (let (lower (module-binding-action "tao3k/yuanxu/module-system/building/program-publication" 'init-compiler-forms))
                 (lower (list path))))))
           (if (and (pair? forms) (keyword? (car forms)) (pair? (cdr forms)))
             (skip-header (cddr forms))
             (datum->syntax (stx-car #'original) (cons 'begin forms)))))
       (expand-declaration #'original)))))

;; The native expander and admitted compiler projection share this generated
;; form. No runtime declaration supplies a source reader or a program factory.
(defsyntax (expand-yuanxu-program-declaration stx)
  (syntax-case stx ()
    ((_ declaration source program)
     (expand-declaration #'declaration #'program #'source))))
