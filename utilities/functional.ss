;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: pure functional helpers for reusable Scheme control-plane code.
;;; Invariant: this module owns algorithms and combinators, not workflow,
;;; sandbox, session, proof, or runtime semantics.

(import (only-in :std/list/list
                 assoc
                 any
                 every
                 find
                 filter
                 filter-map
                 fold
                 fold-right
                 map
                 member
                 remove
                 delete-duplicates/hash
                 duplicates
                 flatten1)
        (only-in :std/string/misc
                 string-drop))

(export yuanxu-fold-left
        yuanxu-fold-right
        yuanxu-map
        yuanxu-find
        yuanxu-filter-map
        yuanxu-remove
        yuanxu-append-map
        yuanxu-any?
        yuanxu-all?
        yuanxu-member?
        yuanxu-set-subset?
        yuanxu-stable-duplicates
        yuanxu-alist?
        yuanxu-list-of?
        yuanxu-string-prefix?
        yuanxu-string-drop-prefix
        yuanxu-predicate-and
        yuanxu-predicate-or
        yuanxu-predicate-exactly-one
        yuanxu-alist-ref/default
        yuanxu-alist-select
        yuanxu-alist-delete-key
        yuanxu-alist-merge-right)

;; yuanxu-fold-left
;;   : (-> Procedure Object [Object] Object)
;;   | doc m%
;;       `yuanxu-fold-left` delegates ordinary left folds to SRFI-1 while
;;       keeping shared control-plane algorithms behind a project-owned name.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-fold-left cons '() '(a b))
;;       ;; => (b a)
;;       ```
;;     %
(def (yuanxu-fold-left combine seed values)
  (fold combine seed values))

;; yuanxu-fold-right
;;   : (-> Procedure Object [Object] Object)
;;   | doc m%
;;       `yuanxu-fold-right` preserves right-associated list construction and
;;       projection order without hand-written recursive loops in callers.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-fold-right cons '() '(a b))
;;       ;; => (a b)
;;       ```
;;     %
(def (yuanxu-fold-right combine seed values)
  (fold-right combine seed values))

;; yuanxu-map
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       `yuanxu-map` is the project-level pure projection boundary for
;;       keeping field extraction and manifest row construction out of
;;       hand-written recursion.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-map (lambda (value) (* value 2)) '(1 2 3))
;;       ;; => (2 4 6)
;;       ```
;;     %
(def (yuanxu-map project values)
  (map project values))

;; yuanxu-find
;;   : (-> Procedure [Object] Object)
;;   | doc m%
;;       `yuanxu-find` is the project-level pure lookup boundary for
;;       replacing recursive scans that return the matching value.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-find odd? '(2 4 5 6))
;;       ;; => 5
;;       ```
;;     %
(def (yuanxu-find predicate values)
  (find predicate values))

;; yuanxu-filter-map
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       `yuanxu-filter-map` is the default projection helper when a mapper
;;       may reject rows by returning `#f`.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-filter-map (lambda (x) (and (odd? x) x)) '(1 2 3))
;;       ;; => (1 3)
;;       ```
;;     %
(def (yuanxu-filter-map project values)
  (filter-map project values))

;; yuanxu-remove
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       `yuanxu-remove` delegates negative filtering to SRFI-1 `remove` so
;;       callers do not hand-roll `(filter (lambda (...) (not ...)) ...)`.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-remove even? '(1 2 3))
;;       ;; => (1 3)
;;       ```
;;     %
(def (yuanxu-remove predicate values)
  (remove predicate values))

;; yuanxu-append-map
;;   : (-> Procedure [Object] [Object])
;;   | doc m%
;;       `yuanxu-append-map` flattens one projection layer and should replace
;;       local map/append loops in ordinary list expansion code.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-append-map (lambda (x) (list x x)) '(a b))
;;       ;; => (a a b b)
;;       ```
;;     %
(def (yuanxu-append-map project values)
  (flatten1 (map project values)))

;; yuanxu-any?
;;   : (-> Procedure [Object] Boolean)
;;   | doc m%
;;       `yuanxu-any?` normalizes SRFI-1 `any` into a strict boolean for
;;       predicates used by contract and policy gates.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-any? symbol? '(1 two))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-any? predicate values)
  (if (any predicate values) #t #f))

;; yuanxu-all?
;;   : (-> Procedure [Object] Boolean)
;;   | doc m%
;;       `yuanxu-all?` normalizes SRFI-1 `every` into a strict boolean for
;;       list-shaped contract predicates.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-all? integer? '(1 2 3))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-all? predicate values)
  (if (every predicate values) #t #f))

;; yuanxu-member?
;;   : (-> Object [Object] Boolean)
;;   | doc m%
;;       `yuanxu-member?` wraps `member` as a strict boolean so callers do
;;       not duplicate `(and (member value values) #t)` in predicates.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-member? 'mode '(owner mode))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-member? value values)
  (if (member value values) #t #f))

;; yuanxu-set-subset?
;;   : (-> [Object] [Object] Boolean)
;;   | contract: compare list-shaped sets without rescanning the allowed set
;;   | complexity: O(requested + allowed) expected time
(def (yuanxu-set-subset? requested allowed)
  (let (allowed-index (make-hash-table))
    (for-each
     (lambda (value)
       (hash-put! allowed-index value #t))
     allowed)
    (yuanxu-all?
     (lambda (value)
       (hash-key? allowed-index value))
     requested)))

;; yuanxu-stable-duplicates
;;   : (-> [Object] [Object])
;;   | doc m%
;;       Returns each duplicated value once, ordered by its first appearance.
;;       The implementation composes the maintained `std/misc/list` hash
;;       algorithms instead of repeatedly scanning an accumulated list.
;;     %
(def (yuanxu-stable-duplicates values)
  (let (duplicate-table (make-hash-table))
    (for-each
     (lambda (entry)
       (hash-put! duplicate-table (car entry) #t))
     (duplicates values))
    (filter
     (lambda (value)
       (hash-key? duplicate-table value))
     (delete-duplicates/hash values from-end?: #t))))

;; yuanxu-alist?
;;   : (-> Object Boolean)
;;   | doc m%
;;       `yuanxu-alist?` recognizes proper association lists without assigning
;;       any domain meaning to the keys or values.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-alist? '((owner . contract)))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-alist? value)
  (and (list? value)
       (yuanxu-all? pair? value)))

;; yuanxu-list-of?
;;   : (-> Procedure Object Boolean)
;;   | doc m%
;;       `yuanxu-list-of?` checks that a value is a list and that every element
;;       satisfies a supplied predicate.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-list-of? symbol? '(alpha beta))
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-list-of? predicate value)
  (and (list? value)
       (yuanxu-all? predicate value)))

;; yuanxu-string-prefix?
;;   : (-> String String Boolean)
;;   | doc m%
;;       `yuanxu-string-prefix?` checks string prefixes without allocating
;;       temporary substrings. Non-string inputs are rejected.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-string-prefix? "src/" "src/contract")
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-string-prefix? prefix value)
  (and (string? prefix)
       (string? value)
       (string-prefix? prefix value)))

;; yuanxu-string-drop-prefix
;;   : (-> String String MaybeString)
;;   | doc m%
;;       `yuanxu-string-drop-prefix` returns the suffix after PREFIX when
;;       VALUE has that prefix; otherwise it returns `#f`.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-string-drop-prefix "src/" "src/contract")
;;       ;; => "contract"
;;       ```
;;     %
(def (yuanxu-string-drop-prefix prefix value)
  (and (yuanxu-string-prefix? prefix value)
       (string-drop value (string-length prefix))))

;; yuanxu-predicate-and
;;   : (-> [Procedure] Procedure)
;;   | doc m%
;;       `yuanxu-predicate-and` builds one predicate that accepts a value only
;;       when every predicate in the supplied list accepts it.
;;
;;       # Examples
;;
;;       ```scheme
;;       ((yuanxu-predicate-and (list integer? positive?)) 3)
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-predicate-and predicates)
  (lambda (value)
    (yuanxu-all?
     (lambda (predicate)
       (predicate value))
     predicates)))

;; yuanxu-predicate-or
;;   : (-> [Procedure] Procedure)
;;   | doc m%
;;       `yuanxu-predicate-or` builds one predicate that accepts a value when
;;       any predicate in the supplied list accepts it.
;;
;;       # Examples
;;
;;       ```scheme
;;       ((yuanxu-predicate-or (list string? symbol?)) 'agent)
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-predicate-or predicates)
  (lambda (value)
    (yuanxu-any?
     (lambda (predicate)
       (predicate value))
     predicates)))

;; yuanxu-predicate-exactly-one
;;   : (-> [Procedure] Procedure)
;;   | doc m%
;;       `yuanxu-predicate-exactly-one` builds one predicate that accepts a
;;       value only when exactly one predicate in the supplied list accepts it.
;;       JSON Schema `oneOf` and mutually exclusive policy branches use this
;;       instead of duplicating counting loops.
;;
;;       # Examples
;;
;;       ```scheme
;;       ((yuanxu-predicate-exactly-one (list string? symbol?)) 'agent)
;;       ;; => #t
;;       ```
;;     %
(def (yuanxu-predicate-exactly-one predicates)
  (lambda (value)
    (= (yuanxu-fold-left
        (lambda (predicate count)
          (if (predicate value)
            (+ count 1)
            count))
        0
        predicates)
       1)))

;; yuanxu-alist-ref/default
;;   : (-> Alist Symbol Object Object)
;;   | doc m%
;;       `yuanxu-alist-ref/default` reads an association-list key and returns
;;       an explicit fallback when the key is absent.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-alist-ref/default '((mode . strict)) 'missing 'fallback)
;;       ;; => fallback
;;       ```
;;     %
(def (yuanxu-alist-ref/default alist key default-value)
  (let (entry (assoc key alist))
    (if entry
      (cdr entry)
      default-value)))

;; : (forall (k v) (-> [k] [(Pair k v)] [(Pair k v)]))
;; yuanxu-alist-select
;;   : (-> [Symbol] Alist Alist)
;;   | doc m%
;;       `yuanxu-alist-select` projects keys in caller-provided order and
;;       drops missing keys without allocating placeholder rows.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-alist-select '(mode owner) '((owner . kernel) (mode . strict)))
;;       ;; => ((mode . strict) (owner . kernel))
;;       ```
;;     %
(def (yuanxu-alist-select keys alist)
  (yuanxu-filter-map
   (lambda (key)
     (let (entry (assoc key alist))
       (and entry
            (cons key (cdr entry)))))
   keys))

;; : (forall (k v) (-> k [(Pair k v)] [(Pair k v)]))
;; yuanxu-alist-delete-key
;;   : (-> Symbol Alist Alist)
;;   | doc m%
;;       `yuanxu-alist-delete-key` removes entries matching one key using
;;       `equal?` key comparison.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-alist-delete-key 'budget '((budget . 10) (mode . strict)))
;;       ;; => ((mode . strict))
;;       ```
;;     %
(def (yuanxu-alist-delete-key key alist)
  (yuanxu-remove
   (lambda (entry)
     (equal? key (car entry)))
   alist))

;; : (forall (k v) (-> [(Pair k v)] [(Pair k v)] [(Pair k v)]))
;; yuanxu-alist-merge-right
;;   : (-> Alist Alist Alist)
;;   | doc m%
;;       `yuanxu-alist-merge-right` returns a deterministic right-biased merge:
;;       entries from the right side override matching keys from the left side.
;;
;;       # Examples
;;
;;       ```scheme
;;       (yuanxu-alist-merge-right '((mode . strict)) '((mode . relaxed)))
;;       ;; => ((mode . relaxed))
;;       ```
;;     %
(def (yuanxu-alist-merge-right left right)
  (yuanxu-fold-right
   (lambda (entry merged)
     (cons entry
           (yuanxu-alist-delete-key (car entry) merged)))
   left
   right))
