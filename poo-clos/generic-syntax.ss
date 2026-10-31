;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generic declarations share the existing kernel and method-bundle parameter.
;;; Class lifecycle, reflection and long-combination parsers are separate owners.
(import :std/stxparam
        (only-in "method-bundle-syntax.ss" %method-declaration-only)
        "objects.ss" "dispatch.ss" "lambda-list.ss"
        (for-syntax :gerbil/expander "declaration-ir-core.ss"
                    (only-in :std/list/list filter-map find iota)))
(export .defgeneric .defmethod
        (phi: +1 clos-generic-binding-identifier lower-optional-bindings lower-key-bindings))

(begin-syntax
  (def (clos-generic-binding-identifier name)
    (let* ((datum (syntax->datum name))
           (base
            (if (symbol? datum)
              (symbol->string datum)
              (string-append "setf-" (symbol->string (cadr datum))))))
      (datum->syntax
       (if (identifier? name) name (cadr (syntax->list name)))
       (string->symbol (string-append base "$poo-clos-generic")))))

  ;;; Built-in combination names are symbolic kernel identities.  Every other
  ;;; identifier remains a hygienic lexical reference to a POO descriptor.
  ;;; Combination arguments configure a fresh inert descriptor at declaration
  ;;; evaluation time, leaving the named combination type unchanged.
  ;; : (-> ClosMethodCombinationReferenceDeclarationIR Syntax)
  (def (lower-method-combination-reference reference)
    (let* ((name
            (clos-method-combination-reference-declaration-ir-name reference))
           (arguments
            (clos-method-combination-reference-declaration-ir-arguments
             reference))
           (base
            (if (memq (syntax->datum name)
                      '(standard + and append list max min nconc or progn))
              (with-syntax ((identity (syntax->datum name))) #'(quote identity))
              name)))
      (if (null? arguments)
        base
        (with-syntax ((base base) ((argument ...) arguments))
          #'(poo-clos-configure-method-combination
             (poo-clos-resolve-method-combination base) argument ...)))))

  ;; : (-> ClosGenericDeclarationIR Syntax Syntax)
  (def (lower-poo-clos-generic ir source)
    (let* ((name (clos-generic-declaration-ir-name ir))
           (binding (clos-generic-binding-identifier name))
           (lambda-ir (clos-generic-declaration-ir-lambda-list ir))
           (required (clos-lambda-declaration-ir-required lambda-ir))
           (optional (clos-lambda-declaration-ir-optional lambda-ir))
           (rest? (if (clos-lambda-declaration-ir-rest lambda-ir) #t #f))
           (keys (clos-lambda-declaration-ir-keys lambda-ir))
           (key? (if (or (pair? keys)
                         (clos-lambda-declaration-ir-allow-other-keys lambda-ir))
                   #t #f))
           (allow-other?
            (if (clos-lambda-declaration-ir-allow-other-keys lambda-ir) #t #f))
           (precedence
            (clos-generic-declaration-ir-argument-precedence-order ir))
           (combination
            (lower-method-combination-reference
             (clos-generic-declaration-ir-method-combination ir)))
           (protocol (clos-generic-declaration-ir-protocol ir))
           (documentation (clos-generic-declaration-ir-documentation ir))
           (generic-class
            (clos-generic-declaration-ir-generic-function-class ir))
           (method-class (clos-generic-declaration-ir-method-class ir))
           (declarations (clos-generic-declaration-ir-declarations ir))
           (methods (clos-generic-declaration-ir-methods ir))
           (arguments (datum->syntax
                       (if (identifier? name) name (cadr (syntax->list name)))
                       (gensym 'arguments)))
           (callable-definition
            (if (identifier? name)
              (with-syntax ((name name) (binding binding)
                            (arguments arguments))
                #'(def (name . arguments)
                    (apply poo-clos-call binding arguments)))
              #'(begin))))
      (with-syntax
          ((name name) (binding binding) (arguments arguments)
           (required-count (length required))
           (optional-count (length optional))
           (rest? rest?) (key? key?) (allow-other? allow-other?)
           ((key-name ...) (map clos-key-declaration-ir-name keys))
           ((precedence-index ...) precedence)
           (combination combination)
           (protocol (or protocol #'#f))
           (documentation (or documentation #'#f))
           (generic-class
            (if generic-class (syntax->datum generic-class)
                'standard-generic-function))
           (method-class
            (if method-class (syntax->datum method-class) 'standard-method))
           ((declaration ...) (map syntax->datum declarations))
           ((method-effect ...)
            (map (lambda (method-ir)
                   (lower-poo-clos-method method-ir source))
                 methods))
           (callable-definition callable-definition))
        (syntax/loc source
          (begin
            (def binding
              (poo-clos-generic-binding
               'name
               (poo-clos-generic-function
                'name required-count rest?: rest?
                optional: optional-count key?: key?
                keys: (list 'key-name ...)
                allow-other-keys?: allow-other?
                argument-precedence-order: (list precedence-index ...)
                method-combination: combination
                protocol: protocol
                documentation: documentation
                generic-function-class: 'generic-class
                method-class: 'method-class
                declarations: '(declaration ...))))
            callable-definition
            method-effect ...
            binding)))))

  ;; : (-> ClosParameterDeclarationIR Syntax)
  (def (lower-method-specializer parameter)
    (case (clos-parameter-declaration-ir-kind parameter)
      ((any) #'(poo-clos-any-specializer))
      ((class)
       (with-syntax ((target (clos-parameter-declaration-ir-target parameter)))
         #'(poo-clos-class-specializer target)))
      ((prototype)
       (with-syntax ((target (clos-parameter-declaration-ir-target parameter)))
         #'(poo-clos-prototype-specializer target)))
      ((eql)
       (with-syntax ((target (clos-parameter-declaration-ir-target parameter)))
         #'(poo-clos-eql-specializer target)))
      (else (error "unknown CLOS specializer IR"))))

  ;; : (-> ClosOptionalDeclarationIR Natural Syntax [Syntax])
  (def (lower-optional-bindings optional index arguments)
    (let ((variable (clos-optional-declaration-ir-variable optional))
          (initform (clos-optional-declaration-ir-initform optional))
          (supplied (clos-optional-declaration-ir-supplied optional)))
      (with-syntax ((variable variable) (initform initform)
                    (index index) (arguments arguments))
        (let (value-binding
              #'(variable
                 (poo-clos-positional-argument
                  arguments index (lambda () initform))))
          (if supplied
            (with-syntax ((supplied supplied))
              (list
               #'(supplied
                  (poo-clos-positional-supplied? arguments index))
               value-binding))
            (list value-binding))))))

  ;; : (-> ClosKeyDeclarationIR Natural Syntax [Syntax])
  (def (lower-key-bindings key start arguments)
    (let ((name (clos-key-declaration-ir-name key))
          (variable (clos-key-declaration-ir-variable key))
          (initform (clos-key-declaration-ir-initform key))
          (supplied (clos-key-declaration-ir-supplied key)))
      (with-syntax ((name name) (variable variable) (initform initform)
                    (start start) (arguments arguments))
        (let (value-binding
              #'(variable
                 (let (entry
                       (poo-clos-key-argument arguments start 'name))
                   (if (car entry) (cdr entry) initform))))
          (if supplied
            (with-syntax ((supplied supplied))
              (list
               value-binding
               #'(supplied
                  (car (poo-clos-key-argument arguments start 'name)))))
            (list value-binding))))))

  ;; : (-> ClosMethodDeclarationIR Syntax Syntax)
  (def (lower-poo-clos-method ir source (deferred? #f))
    (let* ((name (clos-method-declaration-ir-name ir))
           (binding (clos-generic-binding-identifier name))
           (qualifier (clos-method-declaration-ir-qualifier ir))
           (lambda-ir (clos-method-declaration-ir-lambda-list ir))
           (required (clos-lambda-declaration-ir-required lambda-ir))
           (optional (clos-lambda-declaration-ir-optional lambda-ir))
           (rest-variable (clos-lambda-declaration-ir-rest lambda-ir))
           (keys (clos-lambda-declaration-ir-keys lambda-ir))
           (allow-other?
            (if (clos-lambda-declaration-ir-allow-other-keys lambda-ir) #t #f))
           (aux (clos-lambda-declaration-ir-aux lambda-ir))
           (body (clos-method-declaration-ir-body ir))
           (name-template
            (if (identifier? name) name (cadr (syntax->list name))))
           (frame (datum->syntax name-template (gensym 'frame)))
           (arguments (datum->syntax name-template (gensym 'arguments)))
           (call-next (datum->syntax name-template 'call-next-method))
           (next-method-p (datum->syntax name-template 'next-method-p))
           (required-bindings
            (map (lambda (parameter index)
                   (with-syntax
                       ((variable (clos-parameter-declaration-ir-variable parameter))
                        (arguments arguments) (index index))
                     #'(variable (list-ref arguments index))))
                 required (iota (length required))))
           (optional-bindings
            (apply append
                   (map (lambda (optional-value index)
                          (lower-optional-bindings
                           optional-value (+ (length required) index)
                           arguments))
                        optional (iota (length optional)))))
           (tail-start (+ (length required) (length optional)))
           (rest-bindings
            (if rest-variable
              (with-syntax ((variable rest-variable) (arguments arguments)
                            (tail-start tail-start))
                (list #'(variable
                         (poo-clos-rest-arguments arguments tail-start))))
              '()))
           (key-bindings
            (apply append
                   (map (lambda (key)
                          (lower-key-bindings key tail-start arguments))
                        keys)))
           (aux-bindings
            (map (lambda (entry)
                   (with-syntax
                       ((variable (clos-aux-declaration-ir-variable entry))
                        (initform (clos-aux-declaration-ir-initform entry)))
                     #'(variable initform)))
                 aux))
           (specializers (map lower-method-specializer required)))
      (with-syntax
          ((name name) (binding binding) (qualifier qualifier)
           (frame frame) (arguments arguments)
           (call-next call-next) (next-method-p next-method-p)
           ((parameter-binding ...)
            (append required-bindings optional-bindings rest-bindings
                    key-bindings aux-bindings))
           ((specializer ...) specializers)
           ((body ...) body)
           (required-count (length required))
           (optional-count (length optional))
           (rest? (if rest-variable #t #f))
           (key? (if (or (pair? keys) allow-other?) #t #f))
           ((key-name ...) (map clos-key-declaration-ir-name keys))
           (allow-other? allow-other?))
        (let (method-value
              (syntax/loc source
                (poo-clos-method
                 'name (list specializer ...)
                 (lambda (frame . arguments)
                   ;; A nested method declaration in the method's executable
                   ;; body retains normal immediate-registration semantics.
                   (syntax-parameterize ((%method-declaration-only #f))
                     (let* (parameter-binding ...)
                       (let ((call-next
                              (lambda replacement-arguments
                                (apply poo-clos-call-next-method
                                       frame replacement-arguments)))
                             (next-method-p
                              (lambda () (poo-clos-next-method? frame))))
                         body ...))))
                 qualifier: 'qualifier
                 lambda-list:
                 (poo-clos-lambda-list
                  required-count optional-count rest? key?
                  (list 'key-name ...) allow-other?))))
          (if deferred?
            method-value
            (with-syntax ((method-value method-value))
              (syntax/loc source
                (poo-clos-generic-binding-add-method! binding method-value))))))))

)

;; | ClosGenericBinding = POOObject
;; .defgeneric
;;   : (-> Identifier LambdaList GenericOption ...)
;;   | contract: lowers one generic declaration to an explicit mutable binding owner.
;;   | doc m%
;;       `.defgeneric` binds a callable generic and its generation owner.
;;
;;       # Examples
;;
;;       ```scheme
;;       (.defgeneric render (object &key format))
;;       ;; => render$poo-clos-generic
;;       ```
;;     %
(defsyntax (.defgeneric stx)
  (syntax-case stx ()
    ((_ name lambda-list option ...)
     (lower-poo-clos-generic
      (parse-poo-clos-generic-declaration-ir
       #'name #'lambda-list (syntax->list #'(option ...)) stx)
      stx))))

;; | ClosMethod = POOObject
;; .defmethod
;;   : (-> (Identifier SpecializedParameter ...) Body ...)
;;   | contract: lowers lexical next-method bindings and installs one method generation.
;;   | doc m%
;;       `.defmethod` admits one method into the named generic binding.
;;
;;       # Examples
;;
;;       ```scheme
;;       (.defmethod (render (object Point) &key format) object)
;;       ;; => ClosMethod
;;       (.defmethod (render (object (prototype Point.)) &key format) object)
;;       ;; => native POO prototype dispatch, without a shadow CLOS class
;;       ```
;;     %
(defsyntax (.defmethod stx)
  (def (lower ir)
    (lower-poo-clos-method
     ir stx (if (syntax-parameter-value #'%method-declaration-only) #t #f)))
  (syntax-case stx (qualifier)
    ((_ (name parameter ...) (qualifier method-qualifier) body ...)
     (lower
      (parse-poo-clos-method-declaration-ir
       #'name #'method-qualifier #'(parameter ...)
       (syntax->list #'(body ...)) stx)))
    ((_ (name parameter ...) body ...)
     (lower
      (parse-poo-clos-method-declaration-ir
       #'name #'primary #'(parameter ...) (syntax->list #'(body ...)) stx)))
    ((_ name (parameter ...) body ...)
     (lower
      (parse-poo-clos-method-declaration-ir
       #'name #'primary #'(parameter ...) (syntax->list #'(body ...)) stx)))
    ((_ name qualifier lambda-list body ...)
     (lower
      (parse-poo-clos-method-declaration-ir
       #'name #'qualifier #'lambda-list (syntax->list #'(body ...)) stx)))))
