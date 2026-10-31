;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: strict observability data for module-system debugging.
;;; Invariant: observations are strict POO values without lazy slots or runtime adapters.
;;; Intent: make recursive presentation paths visible without participating in them.

(import
        (only-in :yuanxu/utilities/algorithms
                 yuanxu-read-datums/append-map
                 yuanxu-scheme-datum-find)
        (only-in :yuanxu/object-family/syntax
                 defpoo-object-family)
        :yuanxu/utilities/final-projection-syntax)

(export yuanxu-module-observation-kind
        yuanxu-module-observation-prototype
        make-yuanxu-module-observation
        yuanxu-module-observation?
        yuanxu-module-observation-scope
        yuanxu-module-observation-stage
        yuanxu-module-observation-status
        yuanxu-module-observation-count
        yuanxu-module-observation-depth
        yuanxu-module-observation-path
        yuanxu-module-observation-detail
        yuanxu-module-observation-descriptor-realized?
        yuanxu-module-observation-runtime-executed?
        yuanxu-module-observation-recursive-stage?
        yuanxu-module-observation-stage-status
        yuanxu-module-observation-stage/detail
        yuanxu-module-observation-stage/alist
        yuanxu-module-observation->alist
        yuanxu-module-presentation-trace
        yuanxu-module-presentation-trace/add
        yuanxu-poo-slot-authoring-observation-kind
        yuanxu-poo-slot-authoring-observation-prototype
        make-yuanxu-poo-slot-authoring-observation
        yuanxu-poo-slot-authoring-observation?
        yuanxu-poo-slot-authoring-observation-scope
        yuanxu-poo-slot-authoring-observation-slot
        yuanxu-poo-slot-authoring-observation-initializer
        yuanxu-poo-slot-authoring-observation-status
        yuanxu-poo-slot-authoring-observation-detail
        yuanxu-poo-slot-authoring-observation-descriptor-realized?
        yuanxu-poo-slot-authoring-observation-runtime-executed?
        yuanxu-poo-slot-authoring-self-reference?
        yuanxu-scheme-datum-find
        yuanxu-poo-slot-authoring-primitive-slot?
        yuanxu-poo-slot-authoring-status
        yuanxu-poo-slot-authoring-observation/alist
        yuanxu-poo-slot-authoring-observations
        yuanxu-poo-slot-authoring-datum-bindings
        yuanxu-poo-slot-authoring-datum-observations
        yuanxu-poo-slot-authoring-port-observations
        yuanxu-poo-slot-authoring-file-observations
        yuanxu-poo-slot-authoring-summary-kind
        yuanxu-poo-slot-authoring-observation-ok?
        yuanxu-poo-slot-authoring-statuses
        yuanxu-poo-slot-authoring-diagnostics
        yuanxu-poo-slot-authoring-summary)

;;; Observation kind ids are shared by doctor, user-config, and future CLI
;;; surfaces so tooling can recognize one trace vocabulary across projections.
;; : (-> Unit YuanxuModuleObservationKind)
(def yuanxu-module-observation-kind
  "yuanxu.modules.observation.v1")

;;; Observation values are strict native POO objects. They contain only eager
;;; slots, so debugging a lazy `.ref` recursion never creates another lazy path.
;; : (-> Symbol Symbol Symbol Integer Integer [Symbol] Alist Boolean Boolean YuanxuModuleObservation)
(defpoo-object-family
  (prototype yuanxu-module-observation-prototype
             module-observation?
             yuanxu-module-observation?)
  (constructor make-yuanxu-module-observation
               (scope-value scope)
               (stage-value stage)
               (status-value status)
               (count-value count)
               (depth-value depth)
               (path-value path)
               (detail-value detail)
               (descriptor-realized-value descriptor-realized?)
               (runtime-executed-value runtime-executed?))
  (accessors
   (yuanxu-module-observation-scope scope)
   (yuanxu-module-observation-stage stage)
   (yuanxu-module-observation-status status)
   (yuanxu-module-observation-count count)
   (yuanxu-module-observation-depth depth)
   (yuanxu-module-observation-path path)
   (yuanxu-module-observation-detail detail)
   (yuanxu-module-observation-descriptor-realized? descriptor-realized?)
   (yuanxu-module-observation-runtime-executed? runtime-executed?))
  (projections))

;;; Recursive-stage detection is intentionally just path membership. The
;;; framework should flag suspicious projection shape without interpreting
;;; descriptor semantics or executing module loaders.
;; : (-> Symbol [Symbol] Boolean)
(def (yuanxu-module-observation-recursive-stage? stage active-path)
  (and (member stage active-path) #t))

;;; Stage status stays finite and symbolic so test fixtures can assert on it
;;; without parsing messages or stack traces.
;; : (-> Symbol [Symbol] Symbol)
(def (yuanxu-module-observation-stage-status stage active-path)
  (if (yuanxu-module-observation-recursive-stage? stage active-path)
    'recursive-stage
    'ok))

;;; Stage observations record the path after the stage is entered. A repeated
;;; stage therefore carries both a `recursive-stage` status and the full path
;;; needed to reproduce the problematic projection walk.
;; : (forall (a) (-> [a] [a] [a]))
;; : (-> List List List)
(def (yuanxu-module-observation-values/tail values tail)
  (append values tail))

;; : (-> Symbol Symbol Integer [Symbol] Alist YuanxuModuleObservation)
(def (yuanxu-module-observation-stage/detail
      scope
      stage
      count
      active-path
      detail)
  (make-yuanxu-module-observation
   scope
   stage
   (yuanxu-module-observation-stage-status stage active-path)
   count
   (length active-path)
   (yuanxu-module-observation-values/tail active-path (list stage))
   detail
   #f
   #f))

;;; Alist projection is the safe edge for user-interface and doctor outputs.
;; : (-> YuanxuModuleObservation Alist)
(defpoo-final-projection
  yuanxu-module-observation->alist (observation)
  (bindings ())
  (fields ((kind yuanxu-module-observation-kind)
           (scope (yuanxu-module-observation-scope observation))
           (stage (yuanxu-module-observation-stage observation))
           (status (yuanxu-module-observation-status observation))
           (count (yuanxu-module-observation-count observation))
           (depth (yuanxu-module-observation-depth observation))
           (path (yuanxu-module-observation-path observation))
           (detail (yuanxu-module-observation-detail observation))
           (descriptor-realized?
            (yuanxu-module-observation-descriptor-realized? observation))
           (runtime-executed
            (yuanxu-module-observation-runtime-executed? observation)))))

;;; Stage/alist keeps the common presentation path concise while still routing
;;; every trace row through the strict observation record.
;; : (-> Symbol Symbol Integer [Symbol] Alist)
(def (yuanxu-module-observation-stage/alist scope stage count active-path)
  (yuanxu-module-observation->alist
   (yuanxu-module-observation-stage/detail
    scope
    stage
    count
    active-path
    '())))

;;; Trace construction is a simple left-to-right walk over `(stage . count)`
;;; pairs. Repeated stages stay in the output with `recursive-stage` status
;;; instead of raising while the caller is trying to inspect a broken projection.
;; : (-> Symbol [Pair] [Symbol] [Alist])
(def (yuanxu-module-presentation-trace/add scope stage-counts active-path)
  (cond
   ((null? stage-counts) '())
   (else
    (let ((entry (car stage-counts)))
      (cons (yuanxu-module-observation-stage/alist
             scope
             (car entry)
             (cdr entry)
             active-path)
            (yuanxu-module-presentation-trace/add
             scope
             (cdr stage-counts)
             (yuanxu-module-observation-values/tail
              active-path
              (list (car entry)))))))))

;;; Presentation traces are report-only data. They are safe to read before
;;; heavier slots because they do not dereference POO objects or realize modules.
;; : (-> Symbol [Pair] [Alist])
(def (yuanxu-module-presentation-trace scope stage-counts)
  (yuanxu-module-presentation-trace/add scope stage-counts '()))

;;; POO authoring observations inspect source-shaped slot bindings, not POO
;;; objects. This catches `.o slot: slot` style self references before a `.ref`
;;; path can recurse or allocate during debugging.
;; : (-> Unit YuanxuPooSlotAuthoringObservationKind)
(def yuanxu-poo-slot-authoring-observation-kind
  "yuanxu.poo-slot-authoring-observation.v1")

;; : (-> Symbol Symbol Value Symbol Alist Boolean Boolean YuanxuPooSlotAuthoringObservation)
(defpoo-object-family
  (prototype yuanxu-poo-slot-authoring-observation-prototype
             poo-slot-authoring-observation?
             yuanxu-poo-slot-authoring-observation?)
  (constructor make-yuanxu-poo-slot-authoring-observation
               (scope-value scope)
               (slot-value slot)
               (initializer-value initializer)
               (status-value status)
               (detail-value detail)
               (descriptor-realized-value descriptor-realized?)
               (runtime-executed-value runtime-executed?))
  (accessors
   (yuanxu-poo-slot-authoring-observation-scope scope)
   (yuanxu-poo-slot-authoring-observation-slot slot)
   (yuanxu-poo-slot-authoring-observation-initializer initializer)
   (yuanxu-poo-slot-authoring-observation-status status)
   (yuanxu-poo-slot-authoring-observation-detail detail)
   (yuanxu-poo-slot-authoring-observation-descriptor-realized?
    descriptor-realized?)
   (yuanxu-poo-slot-authoring-observation-runtime-executed?
    runtime-executed?))
  (projections))

;; : (forall (a) (-> Symbol a Boolean))
;; : (-> Symbol Value Boolean)
(def (yuanxu-poo-slot-authoring-identifier-reference? identifier datum)
  (cond
   ((symbol? datum) (eq? identifier datum))
   ((vector? datum)
    (yuanxu-poo-slot-authoring-identifier-reference?
     identifier (vector->list datum)))
   ((not (pair? datum)) #f)
   ((memq (car datum) '(quote quasiquote syntax quasisyntax)) #f)
   ;; Native .get/.@ expand their path names to quoted symbols. Only the
   ;; receiver is an expression; a same-named path is not a slot dependency.
   ((and (memq (car datum) '(.get .@)) (pair? (cdr datum)))
    (yuanxu-poo-slot-authoring-identifier-reference? identifier (cadr datum)))
   ;; Native .call quotes a literal method name too. Its receiver and argument
   ;; expressions still participate; a method spelling is not a free reference.
   ((and (eq? (car datum) '.call) (pair? (cdr datum))
         (pair? (cddr datum)) (symbol? (caddr datum)))
    (or (yuanxu-poo-slot-authoring-identifier-reference? identifier (cadr datum))
        (yuanxu-poo-slot-authoring-identifier-reference? identifier (cdddr datum))))
   (else
    (or (yuanxu-poo-slot-authoring-identifier-reference? identifier (car datum))
        (yuanxu-poo-slot-authoring-identifier-reference? identifier (cdr datum))))))

;; : (-> Symbol Value Boolean)
(def (yuanxu-poo-slot-authoring-self-reference? slot initializer)
  (and (symbol? slot)
       (yuanxu-poo-slot-authoring-identifier-reference?
        slot initializer)))

;; : [Symbol]
(def +yuanxu-poo-slot-authoring-primitive-slots+
  '(.o .def .ref .slot? object?))

;;; Boundary: poo slot authoring primitive slot predicate is the policy-visible
;;; edge for module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> Symbol Boolean)
(def (yuanxu-poo-slot-authoring-primitive-slot? slot)
  (and (symbol? slot)
       (member slot +yuanxu-poo-slot-authoring-primitive-slots+)
       #t))

;;; Boundary: poo slot authoring status is the policy-visible edge for module-
;;; system behavior, keeping validation, lookup, or projection responsibilities
;;; centralized for callers.
;; : (-> Symbol Value Symbol)
(def (yuanxu-poo-slot-authoring-status slot initializer)
  (cond
   ((yuanxu-poo-slot-authoring-self-reference? slot initializer)
    'self-referential-slot-initializer)
   ((yuanxu-poo-slot-authoring-primitive-slot? slot)
    'primitive-shadow-slot)
   (else 'ok)))

;;; Boundary: poo slot authoring detail is the policy-visible edge for module-
;;; system behavior, keeping validation, lookup, or projection responsibilities
;;; centralized for callers.
;; : (-> Symbol Value Alist)
(def (yuanxu-poo-slot-authoring-detail slot initializer)
  (cond
   ((yuanxu-poo-slot-authoring-self-reference? slot initializer)
    (list (cons 'code 'poo-slot-initializer-shadows-slot)
          (cons 'rule 'poo-slot-initializer-must-not-shadow-slot-name)
          (cons 'slot slot)
          (cons 'initializer initializer)
          (cons 'recommendation 'rename-local-or-wrap-in-helper)))
   ((yuanxu-poo-slot-authoring-primitive-slot? slot)
    (list (cons 'code 'poo-slot-shadows-poo-primitive)
          (cons 'rule 'poo-slot-must-not-shadow-poo-primitive)
          (cons 'slot slot)
          (cons 'initializer initializer)
          (cons 'recommendation 'rename-slot-or-use-result-prefix)))
   (else '())))

;; : (-> Symbol Symbol Value YuanxuPooSlotAuthoringObservation)
(def (yuanxu-poo-slot-authoring-observation/make scope slot initializer)
  (make-yuanxu-poo-slot-authoring-observation
   scope
   slot
   initializer
   (yuanxu-poo-slot-authoring-status slot initializer)
   (yuanxu-poo-slot-authoring-detail slot initializer)
   #f
   #f))

;; : (-> YuanxuPooSlotAuthoringObservation Alist)
(defpoo-final-projection
  yuanxu-poo-slot-authoring-observation->alist (observation)
  (bindings ())
  (fields ((kind yuanxu-poo-slot-authoring-observation-kind)
           (scope
            (yuanxu-poo-slot-authoring-observation-scope observation))
           (slot
            (yuanxu-poo-slot-authoring-observation-slot observation))
           (initializer
            (yuanxu-poo-slot-authoring-observation-initializer observation))
           (status
            (yuanxu-poo-slot-authoring-observation-status observation))
           (detail
            (yuanxu-poo-slot-authoring-observation-detail observation))
           (descriptor-realized?
            (yuanxu-poo-slot-authoring-observation-descriptor-realized?
             observation))
           (runtime-executed
            (yuanxu-poo-slot-authoring-observation-runtime-executed?
             observation)))))

;; : (-> Symbol Pair Alist)
(def (yuanxu-poo-slot-authoring-observation/alist scope slot-initializer)
   (yuanxu-poo-slot-authoring-observation->alist
   (yuanxu-poo-slot-authoring-observation/make
    scope
    (car slot-initializer)
    (cdr slot-initializer))))

;; : (forall (k v) (-> Symbol [(Pair k v)] [Alist]))
;; : (-> Symbol [Pair] [Alist])
(def (yuanxu-poo-slot-authoring-observations scope slot-initializers)
  (map (lambda (slot-initializer)
         (yuanxu-poo-slot-authoring-observation/alist
          scope
          slot-initializer))
       slot-initializers))

;;; Read-only source inspection recognizes both POO-native slot spellings:
;;; `slot: initializer` and `(slot initializer)`.  It operates on reader data,
;;; never expands `.o`/`.def`, constructs a POO object, or evaluates an
;;; initializer.  In particular, a lexical spelling such as `values: values`
;;; is observable before POO can reinterpret the right hand identifier as a
;;; lazy self-slot lookup. `.cc` is a procedure: override values are evaluated
;;; before constant slots are installed, so that spelling is not a lazy
;;; self-reference and must not be rejected here.
;; : (forall (a) (-> [a] [(Pair Symbol a)]))
;; : (-> List [Pair])
(def (yuanxu-poo-slot-authoring-form-bindings elements)
  (cond
   ((null? elements) '())
   ((not (pair? elements)) '())
   ((and (keyword? (car elements))
         (pair? (cdr elements)))
    (cons (cons (string->symbol (keyword->string (car elements)))
                (cadr elements))
          (yuanxu-poo-slot-authoring-form-bindings (cddr elements))))
   ((and (pair? (car elements))
         (symbol? (caar elements))
         (pair? (cdar elements))
         (null? (cddar elements)))
    (cons (cons (caar elements) (cadar elements))
          (yuanxu-poo-slot-authoring-form-bindings (cdr elements))))
   (else
    (yuanxu-poo-slot-authoring-form-bindings (cdr elements)))))

;; : (forall (a) (-> a [(Pair Symbol a)]))
;; yuanxu-poo-slot-authoring-datum-bindings
;;   : (-> Value [Pair])
;;   | doc m%
;;       Read the POO slot/initializer bindings nested in one Scheme datum
;;       without expanding the form, realizing an object, or evaluating code.
;;       The specialized keyword and parenthesized branches preserve source
;;       order and return only source-shaped pairs for the observation owner.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-poo-slot-authoring-datum-bindings
;;        '(.o values: values (safe safe-value)))
;;       ;; => ((values . values) (safe . safe-value))
;;       ```
;;     %
(def (yuanxu-poo-slot-authoring-datum-bindings/into datum tail)
  (cond
   ((not (pair? datum)) tail)
   ((and (memq (car datum) '(quote quasiquote syntax quasisyntax))
         (pair? (cdr datum)))
    tail)
   (else
    (let* ((head (car datum))
           (object-elements
            (cond
             ((eq? head '.o) (cdr datum))
             ((and (eq? head '.def) (pair? (cdr datum))) (cddr datum))
             (else '())))
           (local-bindings
            (yuanxu-poo-slot-authoring-form-bindings object-elements))
           (cdr-bindings
            (yuanxu-poo-slot-authoring-datum-bindings/into
             (cdr datum)
             tail))
           (child-bindings
            (yuanxu-poo-slot-authoring-datum-bindings/into
             (car datum)
             cdr-bindings)))
      (foldr cons child-bindings local-bindings)))))

(def (yuanxu-poo-slot-authoring-datum-bindings datum)
  (yuanxu-poo-slot-authoring-datum-bindings/into datum '()))

;; : (forall (a) (-> Symbol a [Alist]))
;; yuanxu-poo-slot-authoring-datum-observations
;;   : (-> Symbol Value [Alist])
;;   | doc m%
;;       Project one source datum's POO slot bindings into strict authoring
;;       observations without expanding or evaluating the source.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-poo-slot-authoring-datum-observations
;;        'source '(.o value: value))
;;       ;; => one self-referential-slot-initializer observation
;;       ```
;;     %
(def (yuanxu-poo-slot-authoring-datum-observations scope datum)
  (yuanxu-poo-slot-authoring-observations
   scope
   (yuanxu-poo-slot-authoring-datum-bindings datum)))

;; : (-> Symbol InputPort [Alist])
;; yuanxu-poo-slot-authoring-port-observations
;;   : (-> Symbol InputPort [Alist])
;;   | doc m%
;;       Read every datum from a Scheme port and preserve source order while
;;       projecting POO slot authoring observations.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-poo-slot-authoring-port-observations
;;        'source (open-input-string "(.o value: value)"))
;;       ;; => one self-referential-slot-initializer observation
;;       ```
;;     %
(def (yuanxu-poo-slot-authoring-port-observations scope port)
  (yuanxu-read-datums/append-map
   (cut yuanxu-poo-slot-authoring-datum-observations scope <>)
   port))

;; : (forall (k v) (-> Symbol PathString [(Pair k v)]))
;; : (-> Symbol PathString [Alist])
;; yuanxu-poo-slot-authoring-file-observations
;;   : (-> Symbol PathString [Alist])
;;   | doc m%
;;       Open one Scheme source file and return its reader-native POO authoring
;;       observations without loading the module or realizing an object.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-poo-slot-authoring-file-observations
;;        'module "modules/module-authoring/module-descriptor.ss")
;;       ;; => ordered authoring observations
;;       ```
;;     %
(def (yuanxu-poo-slot-authoring-file-observations scope path)
  (call-with-input-file
   path
   (lambda (port)
     (yuanxu-poo-slot-authoring-port-observations scope port))))

;; : (-> Unit YuanxuPooSlotAuthoringSummaryKind)
(def yuanxu-poo-slot-authoring-summary-kind
  "yuanxu.poo-slot-authoring-summary.v1")

;; : (-> Alist Boolean)
(def (yuanxu-poo-slot-authoring-observation-ok? observation)
  (eq? (cdr (assoc 'status observation)) 'ok))

;; : (forall (k v) (-> [(Pair k v)] [Symbol]))
;; : (-> [Alist] [Symbol])
(def (yuanxu-poo-slot-authoring-statuses observations)
  (map (lambda (observation)
         (cdr (assoc 'status observation)))
       observations))

;;; Boundary: poo slot authoring diagnostics is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (forall (k v) (-> [(Pair k v)] [(Pair k v)]))
;; : (-> [Alist] [Alist])
(def (yuanxu-poo-slot-authoring-diagnostics observations)
  (map (lambda (observation)
         (cdr (assoc 'detail observation)))
       (filter (lambda (observation)
                 (not (yuanxu-poo-slot-authoring-observation-ok?
                       observation)))
               observations)))

;; : (-> Symbol [Alist] Alist)
(defpoo-final-projection
  yuanxu-poo-slot-authoring-summary (scope observations)
  (bindings ((diagnostics
              (yuanxu-poo-slot-authoring-diagnostics observations))))
  (fields ((kind yuanxu-poo-slot-authoring-summary-kind)
           (scope scope)
           (observation-count (length observations))
           (statuses
            (yuanxu-poo-slot-authoring-statuses observations))
           (diagnostic-count (length diagnostics))
           (diagnostics diagnostics)
           (descriptor-realized? #f)
           (runtime-executed #f))))
