;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Contract: pure helpers for contract-boundary normalization.
;;; Invariant: this module owns contract data plumbing, not JSON Schema
;;; semantics, object contracts, or runtime execution.

(import (only-in :std/list/list append-map)
        (only-in :std/string/misc
                 string-drop))

(export yuanxu-contract-key->string
        yuanxu-contract-key->symbol
        yuanxu-contract-key=?
        yuanxu-contract-json-object?
        yuanxu-contract-json-array->list
        yuanxu-contract-object-ref
        yuanxu-contract-option
        yuanxu-contract-string-prefix?
        yuanxu-contract-string-drop-prefix
        yuanxu-contract-member?
        yuanxu-contract-any?
        yuanxu-contract-all?
        yuanxu-contract-project-list
        yuanxu-contract-filter-map
        yuanxu-contract-append-map
        yuanxu-contract-remove
        yuanxu-contract-map-pair-with-diagnostics)

;; yuanxu-contract-key->string
;;   : (-> ContractKey MaybeString)
;;   | doc m%
;;       Convert symbol/string keys at JSON-like contract boundaries to strings.
;;       Other values return #f so callers can produce domain diagnostics.
;;     %
(def (yuanxu-contract-key->string key)
  (cond
   ((string? key) key)
   ((symbol? key) (symbol->string key))
   (else #f)))

;; yuanxu-contract-key->symbol
;;   : (-> ContractKey Symbol)
;;   | doc m%
;;       Convert symbol/string keys to stable Scheme slot symbols.
;;     %
(def (yuanxu-contract-key->symbol key)
  (cond
   ((symbol? key) key)
   ((string? key) (string->symbol key))
   (else 'unknown-contract-key)))

;; yuanxu-contract-key=?
;;   : (-> ContractKey ContractKey Boolean)
;;   | doc m%
;;       Compare symbol/string keys by their string spelling.
;;     %
(def (yuanxu-contract-key=? candidate key)
  (let ((candidate-name (yuanxu-contract-key->string candidate))
        (key-name (yuanxu-contract-key->string key)))
    (and candidate-name key-name (string=? candidate-name key-name))))

;; yuanxu-contract-json-object?
;;   : (-> Object Boolean)
;;   | doc m%
;;       Recognize JSON-like objects represented as alists at contract import
;;       boundaries.
;;     %
(def (yuanxu-contract-json-object? value)
  (and (list? value)
       (if (every pair? value) #t #f)))

;; yuanxu-contract-json-array->list
;;   : (-> Object [Object])
;;   | doc m%
;;       Normalize vector/list JSON-like arrays into lists. Non-array values are
;;       treated as empty because callers decide whether that is diagnostic.
;;     %
(def (yuanxu-contract-json-array->list value)
  (cond
   ((vector? value) (vector->list value))
   ((list? value) value)
   (else '())))

;; yuanxu-contract-any?
;;   : (-> Procedure [Object] Boolean)
;;   | doc m%
;;       Run a SRFI-1 `any` scan at the contract boundary and return a strict
;;       boolean for validators and diagnostics.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-any? string? '(1 "x"))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-contract-any? predicate values)
  (if (any predicate values) #t #f))

;; yuanxu-contract-all?
;;   : (-> Procedure [Object] Boolean)
;;   | doc m%
;;       Run a SRFI-1 `every` scan at the contract boundary and return a strict
;;       boolean for list-shaped contract predicates.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-all? symbol? '(a b))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-contract-all? predicate values)
  (if (every predicate values) #t #f))

;; yuanxu-contract-object-ref
;;   : (forall (k v) (-> [(Pair k v)] k v v))
;;   : (-> Alist ContractKey Object Object)
;;   | result: matched row value or DEFAULT-VALUE
;;   | doc m%
;;       Lookup a symbol/string key in a JSON-like object with explicit fallback.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-object-ref '((type . "object")) 'type #f)
;;       ;; => "object"
;;       ```
;;     %
(def (yuanxu-contract-object-ref object key default-value)
  (let (row (find
             (lambda (candidate)
               (and (pair? candidate)
                    (yuanxu-contract-key=? (car candidate) key)))
             object))
    (if row (cdr row) default-value)))

;; yuanxu-contract-option
;;   : (-> Alist ContractKey Object Object)
;;   | doc m%
;;       Read an optional contract option from a JSON-like alist while keeping
;;       symbol/string key comparison centralized.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-option '((owner . workflow)) 'owner #f)
;;       ;; => workflow
;;       ```
;;     %
(def (yuanxu-contract-option options key default-value)
  (yuanxu-contract-object-ref options key default-value))

;; yuanxu-contract-string-prefix?
;;   : (-> String String Boolean)
;;   | doc m%
;;       Check string prefixes through SRFI-13 without allocating temporary
;;       substrings. Non-string inputs are rejected.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-string-prefix? "#/" "#/definitions/User")
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-contract-string-prefix? prefix value)
  (and (string? prefix)
       (string? value)
       (string-prefix? prefix value)))

;; yuanxu-contract-string-drop-prefix
;;   : (-> String String MaybeString)
;;   | doc m%
;;       Return the suffix after PREFIX when VALUE has that prefix. This keeps
;;       boundary parsers on SRFI-13 string operations instead of hand-written
;;       substring arithmetic.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-string-drop-prefix "#/definitions/" "#/definitions/User")
;;       ;; => "User"
;;       ```
;;     %
(def (yuanxu-contract-string-drop-prefix prefix value)
  (and (yuanxu-contract-string-prefix? prefix value)
       (string-drop value (string-length prefix))))

;; yuanxu-contract-member?
;;   : (-> Object [Object] Boolean)
;;   | doc m%
;;       Wrap SRFI-1 `member` as a strict boolean for enum, seen-set, and
;;       supported-keyword checks.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-member? 'type '(type properties))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-contract-member? value values)
  (if (member value values) #t #f))

;; yuanxu-contract-project-list
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       Project a list through SRFI-1 `map` at the contract boundary so schema
;;       owners do not call generic list primitives directly.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-project-list symbol->string '(a b))
;;       ;; => ("a" "b")
;;       ```
;;     %
(def (yuanxu-contract-project-list projector values)
  (map projector values))

;; yuanxu-contract-filter-map
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       Project and drop rejected rows through SRFI-1 `filter-map`, preserving
;;       encounter order for diagnostics and generated contract slots.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-filter-map (lambda (x) (and x x)) '(#f a))
;;       ;; => (a)
;;       ```
;;     %
(def (yuanxu-contract-filter-map projector values)
  (filter-map projector values))

;; yuanxu-contract-append-map
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       Flatten one projected list layer through SRFI-1 `append-map` for
;;       contract facts that expand one input node into many output rows.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-append-map (lambda (x) (list x x)) '(a b))
;;       ;; => (a a b b)
;;       ```
;;     %
(def (yuanxu-contract-append-map projector values)
  (append-map projector values))

;; yuanxu-contract-remove
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       Remove rows matching a predicate through SRFI-1 `remove`, usually for
;;       bounded contract projections that need explicit deletion semantics.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-remove string? '(a "b" c))
;;       ;; => (a c)
;;       ```
;;     %
(def (yuanxu-contract-remove predicate values)
  (remove predicate values))

;; yuanxu-contract-map-pair-with-diagnostics
;;   : (-> Procedure [Object] [Diagnostic] Pair)
;;   | doc m%
;;       Map values whose projector returns `(value . diagnostics)`, preserving
;;       result order and appending diagnostics in encounter order.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-contract-map-pair-with-diagnostics parse rows '())
;;       ;; => (values . diagnostics)
;;       ```
;;     %
(def (yuanxu-contract-map-pair-with-diagnostics project values diagnostics)
  (fold-right
   (lambda (value accumulated)
     (let (parsed (project value))
       (cons (cons (car parsed) (car accumulated))
             (append (cdr parsed) (cdr accumulated)))))
   (cons '() diagnostics)
   values))
