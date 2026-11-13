;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Closed declaration projection; open source keeps the original reader.
;;; The resolver is captured once by an admitted private wrapper, never a user
;;; purity flag or an alternate cache. POO owns all delayed role values.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/prototype-map prototype-map)
        (only-in :gerbil/expander datum->syntax eval-syntax core-expand import-module resolve-identifier
                 current-expander-context expander-context-id
                 module-context? module-context-path make-top-context
                 current-expander-module-import core-import-module core-module->prelude-context
                 module-context-export module-export-name)
        (only-in :clan/poo/io module-action)
        (only-in :tao3k/yuanxu/module-system/source/compiled-role compiled-role-values)
        (only-in :std/list/list delete-duplicates/hash append-map)
        (rename-in (only-in :tao3k/yuanxu/module-system/source/declaration .def)
                   (.def publication-.def))
        (for-syntax :gerbil/expander (only-in :std/list/list append-map)
                    (only-in :tao3k/yuanxu/module-system/source/observations
                             module-source-measure-operation)))
(export module-deferred-role-exports include-deferred-declaration module-role-values
        current-module-role-resolver module-entry-action module-binding-action deferred-role-values
        wrapper-delivery? wrapper-delivery-value)
(def current-module-role-resolver (make-parameter #f))
(defstruct wrapper-delivery (value) final: #t)

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
                                          (core-module->prelude-context language)))))
        ;; Preserve the invoking reader's import owner. Replacing its hook with
        ;; core-import-module loses dependency provenance on cached imports.
        (when collision? (core-expand '(import :gerbil/core)))
        (core-expand `(import (only-in ,specifier ,binding)))
        (import-module specifier #f #t)
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
(def (module-deferred-role-exports interface-text role-texts
                                  interface-forms: (interface-forms #f)
                                  private-import: (observe-private-import void))
  ;; Only inspect the already guarded byte snapshots. No source initializer,
  ;; macro expander, Type predicate or role loader runs here.
  (with-catch
    (lambda (_open) #f)
    (lambda ()
      ;; Imports belong to Gerbil's binding phase, not to the role payload.
      ;; A normal authored Interface may import its declaration macro explicitly.
      (def declarations
        (let loop ((forms (or interface-forms (call-with-input-string interface-text read-all))))
          (if (and (pair? forms) (pair? (car forms)) (eq? (caar forms) 'import))
            (begin
              (when (ormap (lambda (spec)
                             (and (string? spec)
                                  (member (path-strip-directory spec)
                                    '("types.ss" "objects.ss" "config.ss" "func.ss"))))
                           (cdar forms))
                (error "explicit role imports use native expansion"))
              (loop (cdr forms)))
            forms)))
      (match declarations
        ([['.def (? symbol?) . body]]
         (def rows (closed-rows body))
         (closed-symbol (closed-field rows 'identity:))
         (match (closed-field rows 'features:)
           (['quote (? list? names)]
            (unless (andmap symbol? names) (error "invalid Feature names" names)))
           (value (closed-object value)))
         (def baseline (closed-object (closed-field rows 'core:)))
         (closed-field baseline 'scope-contract:)
         (closed-field baseline 'exports:)
         (when (assq 'requires: baseline) (error "removed Module core field"))
         (def roles (map (lambda (row)
                           (cons (car row)
                             (role-exports (car row) (cdr row) observe-private-import)))
                        role-texts))
         (def names (append-map cdr roles))
         (unless (= (length names) (length (delete-duplicates/hash names)))
           (error "ambiguous closed role exports"))
         roles)
        (else #f)))))

;; The generated role receiver has no implicit lexical slot bindings. Use
;; the same native slot specifications with the current owner resolver.
(def (deferred-role-values load roles)
  (make-object
    slots: (prototype-map
             (append-map
               (lambda (spec)
                 (def role (car spec))
                 (def names (cdr spec))
                 (cons (cons role ($self-slot-spec (lambda (_self) (load role names))))
                       (map (lambda (name)
                              (cons name ($self-slot-spec (lambda (self) (.ref (.ref self role) name)))))
                            names))) roles)
             policy: 'compact)
    defaults: (prototype-map '() policy: 'compact)))

;; A closed payload without local slot references needs the same lazy POO
;; frame, but no per-owner lexical slot transformers.
(def (deferred-payload-object parents fields)
  (make-object
    supers: parents
    slots: (prototype-map
             (map (lambda (field) (cons (car field) ($self-slot-spec (cdr field)))) fields)
             policy: 'compact)
    defaults: (prototype-map '() policy: 'compact)))

;; The native expander seals this recipe after checking lexical bindings.
;; It describes lazy POO slots; each invocation supplies its own role object.
(def (stock-interface-value recipe roles)
  (match recipe
    (['literal value] value)
    (['alias name] (.ref roles name))
    (['error message] (error message))
    (['frame parents . fields]
     (deferred-payload-object (stock-interface-value parents roles)
       (map (lambda (field)
              (cons (car field) (lambda (_self) (stock-interface-value (cdr field) roles))))
            fields)))))

(def (stock-interface-scoped recipe core private)
  (stock-interface-value (cdr recipe) (and (car recipe) (.ref core private))))

(def (stock-interface-core rows private role-specs resolver)
  (deferred-payload-object '()
    (append
      (map (lambda (field)
             (def value (cdr field))
             (cons (car field) (lambda (core) (stock-interface-scoped value core private))))
           rows)
      (list (cons private (lambda (_self) (deferred-role-values resolver role-specs)))))))

(def (stock-interface-publication rows private role-specs resolver)
  (make-wrapper-delivery
    (deferred-payload-object '()
      (map (lambda (field)
             (def value (cdr field))
             (cons (car field)
               (case (car field)
                 ((core) (lambda (_self) (stock-interface-core value private role-specs resolver)))
                 ((identity) (lambda (_self) (stock-interface-value value #f)))
                 (else (lambda (self)
                         (stock-interface-value (cdr value)
                           (and (car value) (.ref (.get self core) private))))))))
           rows))))

(begin-syntax
  (def (rewrite-deferred-declaration input roles-value resolver-value forms rewrap?)
    (with-syntax ((((role exports ...) ...) roles-value)
                  (resolver resolver-value))
     (let ()
       (def loader (genident 'role-loader))
       (def private (genident 'role-values))
       (def constructor (quote-syntax deferred-role-values))
       (def frame-constructor (quote-syntax deferred-payload-object))
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
       (def (plain-fields fields)
         (let loop ((rest (syntax->list fields)) (seen '()) (rows '()))
           (cond
            ((null? rest) (reverse rows))
            ((and (pair? (cdr rest)) (keyword? (stx-e (car rest))))
             (let (key (string->symbol (keyword->string (stx-e (car rest)))))
               (and (not (memq key seen))
                    (not (memq key '(self super inherit bind bind-these)))
                    (not (memq (stx-e (cadr rest)) '(? => =>.+)))
                    (loop (cddr rest) (cons key seen) (cons (cons key (cadr rest)) rows)))))
            (else #f))))
       (def (frame origin parents rows self)
         (def (field row)
           (with-syntax ((key (datum->syntax (stx-car origin) (car row)))
                         (body (cdr row)) (self self))
             #'(cons 'key (lambda (self) body))))
         (with-syntax ((build-frame frame-constructor)
                       (parents-expr parents)
                       ((field ...) (map field rows)))
           (syntax/loc origin (build-frame parents-expr (list field ...)))))
       (def (project-stock-value value context aliases shadowed (recipe? #f))
         ;; Only these fixed Gerbil forms cannot introduce an unlisted alias.
         ;; Keep payload leaves in the owner expander. Unknown forms keep the
         ;; original lexical binding scope and object expansion.
         (def (stock-head? identifier native shadows)
           (and (identifier? identifier)
                (not (memq (stx-e identifier) shadows))
                (not (memq (stx-e identifier) aliases))
                (free-identifier=? (syntax-local-rewrap identifier) native)))
         (def (stock-object expression fields parents self shadows)
           (let (rows (plain-fields fields))
             (and parents rows (not (assq self rows))
                  (let* ((shadows (append (map car rows) (cons self shadows)))
                         (projected (map (lambda (row) (walk (cdr row) shadows)) rows)))
                    (and (andmap identity projected)
                         (let (fields (map (lambda (row body) (cons (car row) (car body))) rows projected))
                           (cons (if recipe? (cons* 'frame (car parents) fields)
                                     (frame expression (car parents) fields (genident 'payload-self)))
                                 (append (cdr parents) (append-map cdr projected)))))))))
         (def (walk expression shadows)
           (cond
            ((identifier? expression)
             (let (name (stx-e expression))
               (and (memq name aliases) (not (memq name shadows))
                    (bound-identifier=? expression (datum->syntax context name))
                    (list (if recipe? (list 'alias name) expression) name))))
            ((let (literal (stx-e expression))
               (or (boolean? literal) (number? literal) (string? literal) (char? literal)))
             (list (if recipe? (list 'literal (stx-e expression)) expression)))
            (else
             (syntax-case expression ()
               ((head datum)
                (stock-head? #'head (quote-syntax quote) shadows)
                (list (if recipe? (list 'literal (syntax->datum #'datum)) expression)))
               ((head message)
                (and (string? (stx-e #'message))
                     (stock-head? #'head (quote-syntax error) shadows))
                (list (if recipe? (list 'error (stx-e #'message)) expression)))
               ((head (:: self parent) field ...)
                (and (eq? (stx-e #'::) '::) (eq? (stx-e #'self) '@)
                     (stock-head? #'head (quote-syntax .o) shadows))
                (stock-object expression #'(field ...) (walk #'parent shadows) '@ shadows))
               ((head field ...)
                (stock-head? #'head (quote-syntax .o) shadows)
                (stock-object expression #'(field ...)
                              (list (if recipe? '(literal ()) #'(quote ()))) 'self shadows))
               (_ #f)))))
         (walk value shadowed))
       (def (wrap value receiver (shadowed '()) (stock-only? #f))
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
         (if direct?
           (with-syntax ((receiver receiver) (private private) (value value))
             (syntax/loc #'value (.get (.get receiver private) value)))
           (let* ((visible (filter (lambda (name) (not (memq (stx-e name) shadowed))) names))
                  (stock (project-stock-value value context (map stx-e visible) shadowed))
                  (needed (if stock (filter (lambda (name) (memq (stx-e name) (cdr stock))) visible) visible)))
             (with-syntax ((receiver receiver) (private private) (value (if stock (car stock) value)))
               (cond
                ((and stock-only? (not stock)) #f)
                ((null? visible) #'value)
                ((null? needed)
                 ;; The nonempty native with-slots evaluates its receiver
                 ;; even when no alias is read. Preserve that POO observation.
                 (with-syntax ((object (genident 'role-receiver)))
                   (syntax/loc #'value
                     (let (object (.get receiver private)) value))))
                (else
                 (with-syntax (((alias ...)
                               (map (lambda (name) (datum->syntax context (stx-e name))) needed)))
                   (syntax/loc #'value
                     (with-slots (alias ...) (.get receiver private) value)))))))))
       (def (role-values)
         (with-syntax ((constructor constructor) (loader loader))
           #'(constructor loader '((role exports ...) ...))))
       (def (named-features? value)
         (match (syntax->datum value)
           (['quote (? list? _names)] #t)
           (else #f)))
       (def (stock-publication form direct?)
         ;; A fully known frame requires no synthesized lexical slot
         ;; transformers. All unknown source still uses declaration .def.
         (call/cc
           (lambda (open)
             (def (known value) (or value (open #f)))
             (def (object-fields value)
               (syntax-case value ()
                 ((head . slots)
                  (and (identifier? #'head)
                       (free-identifier=? (syntax-local-rewrap #'head) (quote-syntax .o)))
                  (known (plain-fields #'slots)))
                 (_ (open #f))))
             (def (field rows key)
               (cdr (known (assq key rows))))
             (def (base-frame origin rows self)
               (if direct? rows (frame origin #'(quote ()) rows self)))
             (def (stock-value value shadows)
               (car (known (project-stock-value value (stx-car form) '() shadows direct?))))
             (def (scoped-value value receiver shadows)
               (if direct?
                 (let* ((context (cond ((identifier? value) value)
                                       ((stx-pair? value) (stx-car value))
                                       (else (stx-car form))))
                        (visible (filter (lambda (name) (not (memq name shadows))) (map stx-e names)))
                        (payload (known (project-stock-value value context visible shadows #t))))
                   (cons (pair? visible) (car payload)))
                 (known (wrap value receiver shadows #t))))
             (syntax-case form ()
               ((head binding . slots)
                (and (identifier? #'binding) (identifier? #'head)
                     (free-identifier=? (syntax-local-rewrap #'head) (quote-syntax publication-.def)))
                (let* ((root-rows (known (plain-fields #'slots)))
                       (root-names (map car root-rows))
                       (root-self (genident 'publication-self))
                       (core (field root-rows 'core))
                       (core-rows (object-fields core))
                       (core-names (map car core-rows))
                       (core-self (genident 'core-self))
                       (core-shadows (append core-names root-names)))
                  (known (and (andmap (cut memq <> '(identity core features tags)) root-names)
                              (assq 'features root-rows)
                              ;; The declaration macro captures the owner-bound
                              ;; Feature reader for named source entrypoints.
                              (not (named-features? (field root-rows 'features)))
                              (andmap (cut memq <> '(scope-contract exports)) core-names)
                              (assq 'scope-contract core-rows)
                              (assq 'exports core-rows)))
                  (def role-receiver
                    (with-syntax ((self root-self)) #'(.get self core)))
                  (def core-body
                    (base-frame core
                      (append
                        (map (lambda (row)
                               (cons (car row) (scoped-value (cdr row) core-self core-shadows)))
                             core-rows)
                        (if direct? '() (list (cons (stx-e private) (role-values)))))
                      core-self))
                  (def root-body
                    (base-frame form
                      (map (lambda (row)
                             (cons (car row)
                                   (case (car row)
                                     ((identity) (stock-value (cdr row) root-names))
                                     ((core) core-body)
                                     (else (scoped-value (cdr row) role-receiver root-names))))) root-rows)
                      root-self))
                  (if direct?
                    (with-syntax ((recipe (datum->syntax #'head root-body))
                                  (private private)
                                  (assemble (quote-syntax stock-interface-publication))
                                  (resolve (quote-syntax current-module-role-resolver)))
                      (syntax/loc form
                        (assemble 'recipe 'private '((role exports ...) ...) (resolve))))
                    (with-syntax ((body root-body))
                      (syntax/loc form (begin (def binding body) (export binding)))))))
               (_ (open #f))))))
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
           (with-syntax ((head head) (options options) (private private)
                         (roles (role-values))
                         ((field ...) (syntax->list
                           (map-fields fields (lambda (_key value) (wrap value self shadows))))))
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
                  ((features:)
                   (if (named-features? value) value (wrap value core-reference shadows)))
                  (else (wrap value core-reference shadows)))))))
              (syntax/loc form (head name . slots)))))))
       (def private? (and (eq? (stx-e #'resolver) #f) (pair? forms) (null? (cdr forms))))
       (def direct #f)
       (def definitions
         (module-source-measure-operation 'reader-interface-rewrite
           (lambda ()
             (map (lambda (form)
                    (let (stock (stock-publication form private?))
                      (if stock
                        (module-source-measure-operation 'reader-shared-frame
                          (lambda () (set! direct private?) stock))
                        (rewrite form)))) forms))))
       (def resolver-expression
         (syntax-case #'resolver ()
           ((kind (role owner (name ...)) ...)
            (eq? (stx-e #'kind) 'compiled)
            (with-syntax ((project (quote-syntax compiled-role-values)))
              #'(lambda ()
                  (lambda (selected _names)
                    (case selected
                      ((role) (project 'owner '(name ...))) ...
                      (else (error "unknown published role" selected)))))))
           (_ (if (eq? (stx-e #'resolver) #f)
                (quote-syntax current-module-role-resolver)
                #'resolver))))
       (with-syntax ((loader loader)
                     ;; The reader supplies the owner through the existing
                     ;; parameter. Keep the binding private to this macro.
                     (resolver resolver-expression))
         (let (expanded
                (stx-wrap-source
                  (core-cons 'begin
                    (if direct definitions (cons #'(def loader (resolver)) definitions)))
                  (stx-source input)))
           (if rewrap? (syntax-local-rewrap expanded) expanded)))))))

(defsyntax (expand-deferred-declaration input)
  (syntax-case input ()
    ((_ roles resolver declaration ...)
     (rewrite-deferred-declaration input #'roles #'resolver
       (syntax->list #'(declaration ...)) #f))))

(defsyntax (include-deferred-declaration input)
  (syntax-case input ()
    ((_ path roles resolver)
     (let-values (((_prelude _id _namespace forms)
                   (module-source-measure-operation 'reader-interface-read
                     (lambda () (core-read-module/sexp (stx-e #'path))))))
       (let split ((forms forms) (imports '()))
         (cond
          ((and (pair? forms) (stx-pair? (car forms))
                (eq? (stx-e (stx-car (car forms))) 'import))
           (split (cdr forms) (cons (car forms) imports)))
          ((null? imports)
           ;; Preserve the original reader marks and direct private delivery.
           (rewrite-deferred-declaration input #'roles #'resolver forms #t))
          (else
           ;; Establish authored native imports before expanding the declaration.
           (with-syntax (((import-form ...) (map syntax-local-rewrap (reverse imports)))
                         ((declaration ...) (map syntax-local-rewrap forms)))
             #'(begin import-form ...
                 (expand-deferred-declaration roles resolver declaration ...))))))))))
