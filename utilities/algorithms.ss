;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Reusable algorithmic functions for the Yuanxu core.

(export yuanxu-memoize
        yuanxu-read-datums/append-map
        yuanxu-scheme-datum-find
        yuanxu-make-value-index
        yuanxu-value-index-put!
        yuanxu-value-index-ref
        yuanxu-directory-files-recursive
        yuanxu-make-frontier-state
        yuanxu-frontier-state-ready-ids
        yuanxu-frontier-state-complete!)

;;; Stream Scheme datums from a port while preserving the source order of the
;;; zero-or-more values projected from each datum.  `read-all` is preferable
;;; when callers actually need the complete datum list; observation owners use
;;; this helper so a large source file never has to be materialized twice.
;; : (forall (a) (-> (-> SchemeDatum [a]) InputPort [a]))
(def (yuanxu-read-datums/append-map project port)
  (let read-next ((values-rev '()))
    (let (datum (read port))
      (if (eof-object? datum)
        (reverse values-rev)
        (read-next (foldl cons values-rev (project datum)))))))

;;; Find the first truthy projection in inert Scheme reader data. Quoted syntax
;;; stays opaque. This core owner deliberately uses the native pair walk: a
;;; std/list import here leaks into generated .ssi consumers, and pair walking
;;; is also required for dotted source forms that list combinators reject.
;; : (-> (-> Value Value) Value Value)
(def (yuanxu-scheme-datum-find predicate datum)
  (cond
   ((vector? datum)
    (or (predicate datum)
        (yuanxu-scheme-datum-find predicate (vector->list datum))))
   ((not (pair? datum)) (predicate datum))
   ((and (memq (car datum) '(quote quasiquote syntax quasisyntax))
         (pair? (cdr datum)))
    #f)
   (else
    (or (predicate datum)
        (yuanxu-scheme-datum-find predicate (car datum))
        (yuanxu-scheme-datum-find predicate (cdr datum))))))

;;; One deterministic tree walk shared by source observability, build
;;; projection, and User Interface discovery. The tail accumulator avoids
;;; repeatedly appending complete child result lists on broad directory trees.
(def (yuanxu-directory-files-recursive/into path tail)
  (let (info (file-info path))
    (cond
     ((eq? (file-info-type info) 'regular) (cons path tail))
     ((eq? (file-info-type info) 'directory)
      (foldr (lambda (name rest)
               (yuanxu-directory-files-recursive/into
                (path-expand name path)
                rest))
             tail
             (list-sort string<? (directory-files path))))
     (else tail))))

(def (yuanxu-directory-files-recursive path)
  (yuanxu-directory-files-recursive/into path '()))

;; Presence is checked separately so an explicitly cached #f remains cached.
(def (yuanxu-memoize key-of compute)
  (let (entries (make-hash-table))
    (lambda (input)
      (let (key (key-of input))
        (if (hash-key? entries key)
          (hash-get entries key)
          (let (value (compute input))
            (hash-put! entries key value)
            value))))))

;; Runner-local DAG values use structural node ids and may legitimately hold
;; #f, so lookup reports presence separately from the stored value.
(def (yuanxu-make-value-index)
  (make-hash-table))

(def (yuanxu-value-index-put! index id value)
  (hash-put! index id value)
  index)

(def (yuanxu-value-index-ref index id)
  (if (hash-key? index id)
    (values #t (hash-get index id))
    (values #f #f)))

;; Incremental frontier state keeps graph traversal proportional to the graph
;; plus the frontier payloads emitted by receipts. Node order remains the
;; canonical plan order through ordinal insertion.
(defstruct yuanxu-frontier-state
  (ready dependents remaining ordinals)
  transparent: #t)

(def (yuanxu-frontier-state-ready-ids state)
  (yuanxu-frontier-state-ready state))

(def (yuanxu-make-frontier-state nodes id-of ordinal-of dependencies-of)
  (let ((dependents (make-hash-table))
        (remaining (make-hash-table))
        (ordinals (make-hash-table)))
    (let loop ((rest nodes) (ready-rev '()))
      (if (null? rest)
        (make-yuanxu-frontier-state
         (reverse ready-rev) dependents remaining ordinals)
        (let* ((node (car rest))
               (id (id-of node))
               (dependencies (dependencies-of node)))
          (hash-put! ordinals id (ordinal-of node))
          (hash-put! remaining id (length dependencies))
          (for-each
           (lambda (dependency-id)
             (hash-put! dependents dependency-id
                        (cons id (or (hash-get dependents dependency-id) '()))))
           dependencies)
          (loop (cdr rest)
                (if (null? dependencies) (cons id ready-rev) ready-rev)))))))

(def (yuanxu-frontier-insert id ids ordinals)
  (cond
   ((null? ids) (list id))
   ((< (hash-get ordinals id) (hash-get ordinals (car ids)))
    (cons id ids))
   (else
    (cons (car ids)
          (yuanxu-frontier-insert id (cdr ids) ordinals)))))

(def (yuanxu-frontier-remove id ids)
  (cond
   ((null? ids) '())
   ((equal? id (car ids)) (cdr ids))
   (else (cons (car ids) (yuanxu-frontier-remove id (cdr ids))))))

(def (yuanxu-frontier-state-complete! state completed-id)
  (let ((remaining (yuanxu-frontier-state-remaining state))
        (ordinals (yuanxu-frontier-state-ordinals state)))
    (let loop
        ((dependents
          (reverse
           (or (hash-get
                (yuanxu-frontier-state-dependents state) completed-id)
               '())))
         (ready
          (yuanxu-frontier-remove
           completed-id (yuanxu-frontier-state-ready state))))
      (if (null? dependents)
        (begin
          (yuanxu-frontier-state-ready-set! state ready)
          state)
        (let* ((dependent-id (car dependents))
               (next-count (- (hash-get remaining dependent-id) 1)))
          (hash-put! remaining dependent-id next-count)
          (loop (cdr dependents)
                (if (zero? next-count)
                  (yuanxu-frontier-insert dependent-id ready ordinals)
                  ready)))))))
