;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Closed declaration projection; open source keeps the original reader.
;;; The resolver is captured once by an admitted private wrapper, never a user
;;; purity flag or an alternate cache. POO owns all delayed role values.
(import (runtime: :clan/poo/object)
        (only-in :gerbil/expander datum->syntax eval-syntax resolve-identifier
                 import-module current-expander-context expander-context-id
                 module-context? module-context-path make-top-context
                 current-expander-module-import core-import-module core-module->prelude-context
                 module-context-export module-export-name)
        (only-in :gerbil/runtime/loader load-module)
        (only-in :clan/poo/io module-action)
        (only-in :std/list/list delete-duplicates/hash append-map)
        (for-syntax :gerbil/expander (only-in :std/list/list append-map)))
(export module-deferred-role-exports include-deferred-declaration module-role-values module-import-role-values
        current-module-role-resolver module-entry-action module-binding-action)
(def current-module-role-resolver (make-parameter #f))

;; Runtime source evaluation and compiled runtime loading have different
;; initialization authorities. Inspect the actual creating owner, not a user
;; flag, a visible global, file existence or a caught loader error.
(def (module-entry-action owner module binding)
  (def context (current-expander-context))
  (if (and (module-context? context)
           (eq? owner (expander-context-id context))
           (string? (module-context-path context))
           (equal? ".ss" (path-extension (module-context-path context))))
    (source-entry-action module binding)
    (module-action module binding)))
(def (source-entry-action module binding)
  ;; Only immutable identifiers enter the closure, not the creating context.
  ;; Official expander/import state owns source initialization and its errors.
  (def specifier (string->symbol (string-append ":" module)))
  (lambda (arguments)
    (parameterize ((current-expander-context (make-top-context))
                   (current-expander-module-import core-import-module))
      (eval-syntax `(import ,specifier)))
    (apply (eval binding) arguments)))

;; Platform value factories need a public binding, not eager initialization of
;; every runtime dependency in a whole facade. Runtime import owns the defining
;; context and its errors; resolve anew so reloads never retain an old procedure.
;; This is not the runtime-entry/publication admission boundary above.
(def (module-binding-action module binding)
  (def specifier (string->symbol (string-append ":" module)))
  (lambda (arguments)
    ;; Gerbil owns the shared weak language frame. A factory needs one strong
    ;; public binding, not a fresh copy of every gerbil/core alias. Resolve the
    ;; runtime owner on each invocation; retain no function or approval here.
    (let* ((language (core-import-module ':gerbil/core))
           ;; A colliding name must retain the original strong-import rules,
           ;; including runtime duplicate-binding errors. Actual export metadata,
           ;; not a caller flag, determines this conservative fallback.
           (collision? (ormap (lambda (entry) (eq? binding (module-export-name entry)))
                              (module-context-export language))))
      (parameterize ((current-expander-context
                      (make-top-context (and (not collision?)
                                          (core-module->prelude-context language))))
                     (current-expander-module-import core-import-module))
        (when collision? (eval-syntax '(import :gerbil/core)))
        (eval-syntax `(import (only-in ,specifier ,binding)))
        (apply (eval-syntax binding) arguments)))))
(def (closed-rows body)
  (let loop ((rest body) (seen '()) (rows '()))
    (match rest
      ([] (reverse rows))
      ([(? keyword? key) value . tail]
       (when (memq key seen) (error "duplicate closed declaration field" key))
       (loop tail (cons key seen) (cons (cons key value) rows)))
      (else (error "open declaration field" rest)))))
(def (closed-field rows key)
  (cond ((assq key rows) => cdr)
        (else (error "missing closed declaration field" key))))
(def (closed-object expression)
  (match expression
    (['.o [':: (? symbol?) ['@list]] . body] (closed-rows body))
    (['.o . body] (closed-rows body))
    (else (error "open declaration object" expression))))
(def (closed-symbol expression)
  (match expression
    (['quote (? symbol? name)] name)
    (else (error "calculated declaration identity" expression))))
(def (role-exports role text observe-private-import)
  (def forms (call-with-input-string text read-all))
  ;; The reader expands private import metadata through its existing confined
  ;; source resolver before publishing the delayed runtime values.
  (def (source-path? spec)
    (cond ((string? spec) #t)
          ((pair? spec) (or (source-path? (car spec)) (source-path? (cdr spec))))
          (else #f)))
  (for-each (lambda (form)
    (match form
      (['import . specs]
       (when (source-path? specs) (observe-private-import role)))
      ([(? symbol? head) . _]
       ;; Syntax exports and phase initializers are not runtime tuple fields.
       ;; Keep their original runtime contexts and one-time expansion owner.
       (unless (memq head '(export def defvalues defstruct defclass define-type
                           .def .defgeneric .defmethod))
         (error "open role declaration requires guarded reader" role head)))
      (else (error "open role body requires guarded reader" role)))) forms)
  (def names
    (append-map
      (lambda (form)
        (match form
          (['export . names]
           (unless (andmap symbol? names) (error "open role exports" role))
           names)
          (else '()))) forms))
  (delete-duplicates/hash
    (if (eq? role 'config) (cons 'Config names) names)))

;; Internal projection after the runtime role body has expanded. The expander
;; owns optional Config binding, just as in export-role-config.
(def (module-role-values names)
  (def fields
    (filter (lambda (name)
              (or (not (eq? name 'Config))
                  (resolve-identifier (datum->syntax #f name))))
      names))
  (object<-alist
    (map (lambda (name)
           (cons name (eval-syntax (datum->syntax #f name))))
      fields)))
;; Runtime import owns context identity and its one-time initializer. The POO
;; role slot owns demand; this function has no loaded-state or result registry.
(def (module-import-role-values path names)
  ;; Import supplies lexical bindings; only the official runtime loader
  ;; initializes the compiled role. A context left by std/make's expansion is
  ;; metadata, not permission to interpret its body a second time.
  (def context (import-module path))
  (load-module (symbol->string (expander-context-id context)))
  (parameterize ((current-expander-context context))
    (module-role-values names)))
(def (module-deferred-role-exports interface-text role-texts
                                  private-import: (observe-private-import void))
  ;; Only inspect the already guarded byte snapshots. No source initializer,
  ;; macro expander, Type predicate or role loader runs here.
  (with-catch
    (lambda (_open) #f)
    (lambda ()
      (match (call-with-input-string interface-text read-all)
        ([['.def (? symbol?) . body]]
         (def rows (closed-rows body))
         (closed-symbol (closed-field rows 'identity:))
         (closed-object (closed-field rows 'features:))
         (def baseline (closed-object (closed-field rows 'core:)))
         (closed-field baseline 'scope-contract:)
         (closed-field baseline 'exports:)
         (for-each
           (lambda (entry)
             (closed-symbol (closed-field (closed-object (cdr entry)) 'module-id:)))
           (closed-object (closed-field baseline 'requires:)))
         (def roles (map (lambda (row)
                           (cons (car row)
                             (role-exports (car row) (cdr row) observe-private-import)))
                        role-texts))
         (def names (append-map cdr roles))
         (unless (= (length names) (length (delete-duplicates/hash names)))
           (error "ambiguous closed role exports"))
         roles)
        (else #f)))))

(defsyntax (include-deferred-declaration input)
  (syntax-case input ()
    ((_ path ((role exports ...) ...) resolver)
     (let-values (((_prelude _id _namespace forms) (core-read-module/sexp (stx-e #'path))))
       (def loader (genident 'role-loader))
       (def private (genident 'role-values))
       (def roles-self (genident 'roles-self))
       (def specifications (syntax->list #'((role exports ...) ...)))
       (def names (append-map (lambda (spec) (cdr (syntax->list spec))) specifications))
       (def (map-fields rows transform)
         (syntax-case rows ()
           (() #'())
           ((key value . tail)
            (with-syntax ((value (transform #'key #'value))
                          (next (map-fields #'tail transform)))
              #'(key value . next)))
           (_ (raise-syntax-error #f "closed fields require keyword/value pairs" rows))))
       (def (map-object object transform)
         (syntax-case object ()
           ((head . fields)
            (with-syntax ((fields (map-fields #'fields transform))) (syntax/loc object (head . fields))))))
       (def (wrap value receiver (shadowed '()))
         (def context (if (identifier? value) value
                         (if (stx-pair? value) (stx-car value) (stx-car (car forms)))))
         ;; A bare exported alias has exactly the native with-slots meaning:
         ;; evaluate this private receiver once and read that same slot. Do not
         ;; install every other role's identifier transformer for this case.
         ;; Compound syntax and unknown identifiers retain the original scope;
         ;; their macros may depend on use-site bindings that a scan cannot see.
         (def direct?
           (and (identifier? value)
                (not (memq (stx-e value) shadowed))
                (ormap (lambda (name)
                         (bound-identifier=? value (datum->syntax context (stx-e name)))) names)))
         (with-syntax ((receiver receiver) (private private) (value value)
                       ((alias ...) (map (lambda (name) (datum->syntax context (stx-e name)))
                         (filter (lambda (name) (not (memq (stx-e name) shadowed))) names))))
           (if direct?
             (syntax/loc #'value (.get (.get receiver private) value))
             (syntax/loc #'value
               (with-slots (alias ...) (.get receiver private) value)))))
       (def (wrap-requires value receiver (shadowed '()))
         (map-object value
           (lambda (_alias spec)
             (map-object spec
               (lambda (key value)
                 (if (eq? (stx-e key) 'contract:) (wrap value receiver shadowed) value))))))
       (def (role-values)
         (with-syntax ((self roles-self)
                       ((row ...)
                        (append-map
                          (lambda (spec)
                            (syntax-case spec ()
                              ((role name ...)
                               (with-syntax ((loader loader) (self roles-self))
                                 (cons #'(role (loader 'role '(name ...)))
                                   (syntax->list #'((name (.ref (.ref self 'role) 'name)) ...)))))))
                          specifications)))
           ;; All generated formulas use hygienic loader or explicit self.
           ;; Native computed slots still receive the current POO receiver;
           ;; implicit lexical aliases add no binding used by this object.
           #'(.o self: self bind-these: #f row ...)))
       (def (wrap-core core root-shadows)
         ;; Keep fields as a runtime syntax list; append one private lazy slot.
         (def (build head options self fields)
           (def field-list (syntax->list fields))
           (def shadows
             (append root-shadows (cons (stx-e self)
               (let loop ((rest field-list))
                 (if (null? rest) '()
                   (cons (string->symbol (keyword->string (stx-e (car rest))))
                         (loop (cddr rest))))))))
           (def aliases
             (let* ((row (let loop ((rest field-list))
                           (if (eq? (stx-e (car rest)) 'requires:) (cadr rest)
                               (loop (cddr rest)))))
                    (specs (cdr (syntax->list row))))
               (let loop ((rest specs))
                 (if (null? rest) '()
                   (cons (string->symbol (keyword->string (stx-e (car rest))))
                         (loop (cddr rest)))))))
           (with-syntax ((head head) (options options) (private private)
                         (roles (role-values))
                         ((field ...) (syntax->list
                           (map-fields fields
                             (lambda (key value)
                               (if (eq? (stx-e key) 'requires:)
                                 (wrap-requires value self shadows)
                                 (wrap value self (if (eq? (stx-e key) 'exports:)
                                                    (append aliases shadows) shadows))))))))
             (syntax/loc core (head options field ... (private roles)))))
         (syntax-case core ()
           ((head (:: self parents) . fields) (build #'head #'(:: self parents) #'self #'fields))
           ((head . fields)
            (let (self (genident 'core-self))
              (with-syntax ((self self)) (build #'head #'(:: self []) #'self #'fields))))))
       (def (rewrite form)
         (syntax-case form ()
           ((head name . slots)
            (let ()
            (def core-reference (datum->syntax #'head 'core (stx-source form)))
            (def shadows
              (let loop ((rest (syntax->list #'slots)))
                (if (null? rest) '()
                  (cons (string->symbol (keyword->string (stx-e (car rest))))
                        (loop (cddr rest))))))
            (with-syntax ((slots (map-fields #'slots
              (lambda (key value)
                (case (stx-e key)
                  ((core:) (wrap-core value shadows))
                  ((identity:) value)
                  (else (wrap value core-reference shadows)))))))
              (syntax/loc form (head name . slots)))))))
       (with-syntax ((loader loader)
                     (resolver (if (identifier? #'resolver)
                                 (datum->syntax (stx-car (car forms)) (stx-e #'resolver))
                                 #'resolver)))
         (syntax-local-rewrap
           (stx-wrap-source
             (core-cons 'begin
               (cons #'(def loader (resolver)) (map rewrite forms)))
             (stx-source input))))))))
