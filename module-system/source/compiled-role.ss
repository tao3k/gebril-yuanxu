;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Export resolution belongs to compilation; runtime demand uses Gerbil loading.
(import (only-in :clan/poo/object object<-alist)
        (only-in :gerbil/runtime/loader load-module)
        (for-syntax :gerbil/expander
                    (only-in :gerbil/compiler compile-module)
                    (only-in :gerbil/compiler/base module-id->path-string)))
(export compiled-role-values)

(begin-syntax
  ;; The compiler facade loads its driver; this native driver operation is
  ;; resolved only while expanding code, never by a deployed Module scope.
  (def find-runtime-module-deps (eval 'gxc#find-runtime-module-deps))
  ;; The compiler's public Module ID encoding owns the static unit basename.
  ;; Dynamic Gerbil objects have different generation-local unit names.
  (def (compiled-unit-name context)
    (string->symbol
      (string-join (string-split (module-id->path-string (expander-context-id context)) #\/) "__")))
  (def (runtime-export-binding entry)
    (let unwrap ((binding (core-resolve-module-export entry))
                 (context (module-export-context entry)))
      (cond
       ((import-binding? binding)
        (unwrap (import-binding-e binding) (import-binding-context binding)))
       ((alias-binding? binding)
        (parameterize ((current-expander-marks '()))
          (resolve-identifier (alias-binding-e binding) 0 context)))
       (else binding))))
  (def (compiled-role-context owner origin)
    (def context (core-context-top (current-expander-context) module-context?))
    ;; The compiler already imported the prepared role through for-template.
    ;; Re-resolving its public name would discard that admitted source context
    ;; and can select the original unwrapped role or stale installed metadata.
    (def (find-role imports)
      (and (pair? imports)
        (let* ((entry (car imports))
               (source (cond ((import-set? entry) (import-set-source entry))
                             ((module-import? entry)
                              (module-export-context (module-import-source entry)))
                             ((module-context? entry) entry)
                             (else #f))))
          (if (and (module-context? source) (eq? owner (expander-context-id source)))
            source
            (find-role (cdr imports))))))
    (or (and context (find-role (module-context-import context)))
        (raise-syntax-error #f "compiled role requires its declared template import" origin owner)))
  (def (role-runtime-bindings context names origin)
    (def exports (make-hash-table-eq))
    (for-each
      (lambda (entry)
        (when (zero? (module-export-phi entry))
          (let (name (module-export-name entry))
            (hash-put! exports name
              (cons entry (or (hash-get exports name) '()))))))
      (module-context-export context))
    (filter identity (map
      (lambda (name)
        (def entries (hash-get exports name))
        ;; Config is the existing optional role capability. Its role wrapper
        ;; exports it only when actually bound; absence is not a fabricated value.
        (if (and (not entries) (eq? name 'Config)
                 (string-suffix? "/config" (symbol->string (expander-context-id context))))
          #f
          (begin
            (unless entries
              (raise-syntax-error #f "compiled role requires one runtime export" origin name))
            (let* ((bindings
                     ;; Use the same export resolver as Gerbil's compiler.
                     ;; It preserves marked export keys and alias substitution.
                     (map runtime-export-binding entries))
                   (binding (car bindings)))
              ;; Explicit Config and its implicit role export may name the
              ;; same binding twice. Preserve that native identity; conflicting
              ;; identities cannot be collapsed by their public spelling.
              (unless (andmap (lambda (other) (eq? binding other)) (cdr bindings))
                (raise-syntax-error #f "compiled role requires one runtime export" origin name))
              (unless (runtime-binding? binding)
                (raise-syntax-error #f "compiled role export is not a runtime value" origin name))
              (cons name (binding-id binding)))))) names))))

(defsyntax (compiled-role-values stx)
  (syntax-case stx (quote)
    ((_ (quote owner) (quote (name ...)))
     (let* ((owner (stx-e #'owner))
            (names (syntax->datum #'(name ...)))
            (context (compiled-role-context owner stx))
            (rows (role-runtime-bindings context names stx))
            (namespace (module-context-ns context))
            (owns-export?
              (or (not (string? namespace))
                  (ormap (lambda (row)
                           (string-prefix? (string-append namespace "#")
                             (symbol->string (cdr row)))) rows)))
            (dependencies (map compiled-unit-name (find-runtime-module-deps context))))
       (with-syntax ((owner (symbol->string (expander-context-id context)))
                     (creator (compiled-unit-name
                                (core-context-top (current-expander-context) module-context?)))
                     (unit (compiled-unit-name context))
                     (owns-export? owns-export?)
                     ((dependency-unit ...) dependencies)
                     (((public . identifier) ...) rows))
         ;; A registered static creator is the actual linked-program boundary,
         ;; not a caller flag or a failed file lookup. Native demand activates
         ;; its registered descriptor; a missing role must never load a checkout.
         ;; Dynamic library consumption keeps Gerbil's ordinary loader protocol.
         #'(begin
             (if (##lookup-registered-module 'creator)
               (begin
                 (when (and owns-export? (not (##lookup-registered-module 'unit)))
                   (error "compiled Module role is absent from program" owner))
                 ;; Static SCM bodies omit the dynamic wrapper's dependency
                 ;; loads. Demand the compiler's ordered runtime closure first;
                 ;; Gambit retains initialization state and once-only execution.
                 ;; Empty reexport facades have no descriptor or body to run.
                 (for-each
                   (lambda (dependency)
                     (when (##lookup-registered-module dependency)
                       (##load-module dependency)))
                   '(dependency-unit ... unit)))
               (load-module owner))
             (object<-alist
               (list
                 (cons 'public
                   (let (value (##global-var-ref (##make-global-var 'identifier)))
                     (when (##unbound? value)
                       (error "compiled Module export is uninitialized" owner 'identifier))
                     value)) ...))))))
    (_ (raise-syntax-error #f "compiled role requires literal owner and exports" stx))))
