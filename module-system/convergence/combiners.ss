;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Algebraic horizontal peer combiners (`exclusive`, `refine`, `union`, `meet`)
;;; and vertical C4 band precedence without magic integer priorities.

(import (only-in :clan/poo/object .o .ref .slot? .all-slots object? object<-alist)
        (only-in :std/list/list filter find)
        (only-in ./types
                 governance-envelope-meet make-convergence-diagnostic))
(export list-dedup-union
        combine-peer-values
        apply-band-value
        merge-band-contributions)

(def (list-dedup-union a b)
  (let loop ((rest (append (if (list? a) a '()) (if (list? b) b '())))
             (seen '())
             (acc '()))
    (if (null? rest)
      (reverse acc)
      (let ((x (car rest)))
        (if (member x seen)
          (loop (cdr rest) seen acc)
          (loop (cdr rest) (cons x seen) (cons x acc)))))))

(def (refine-poo-objects base overlay)
  (cond
   ((and (object? base) (object? overlay))
    (let* ((base-slots (.all-slots base))
           (over-slots (.all-slots overlay))
           (all-keys (list-dedup-union base-slots over-slots)))
      (object<-alist
       (map (lambda (k)
              (cond
               ((and (.slot? base k) (.slot? overlay k))
                (cons k (refine-poo-objects (.ref base k) (.ref overlay k))))
               ((.slot? overlay k) (cons k (.ref overlay k)))
               (else (cons k (.ref base k)))))
            all-keys))))
   (else overlay)))

;; Horizontal same-band peer combination (INV-4 & INV-5):
;; Returns (values ok? merged-or-#f diagnostic-or-#f).
(def (combine-peer-values module-id slot-spec left-src left-val right-src right-val)
  (let ((combiner (.ref slot-spec 'combiner))
        (slot-name (.ref slot-spec 'name))
        (meet-fn (.ref slot-spec 'meet-fn)))
    (case combiner
      ((exclusive)
       (if (equal? left-val right-val)
         (values #t left-val #f)
         (values #f #f
                 (make-convergence-diagnostic
                  'peer-exclusive-conflict
                  module-id slot-name left-src right-src
                  (string-append "Disagreeing same-band exclusive values for "
                                 (symbol->string module-id) "." (symbol->string slot-name))))))
      ((union)
       (values #t (list-dedup-union left-val right-val) #f))
      ((refine)
       (values #t (refine-poo-objects left-val right-val) #f))
      ((meet)
       (let ((fn (or meet-fn governance-envelope-meet)))
         (values #t (fn left-val right-val) #f)))
      (else
       (values #f #f
               (make-convergence-diagnostic
                'unknown-combiner module-id slot-name left-src right-src
                "Unsupported slot combiner"))))))

;; Vertical cross-band C4 composition (Band_low < Band_high):
;; Higher band overrides `exclusive`, refines `refine`, unions `union`, and
;; ALWAYS monotonically meets `meet` (INV-5: escalation is unrepresentable).
(def (apply-band-value slot-spec lower-val higher-val)
  (let ((combiner (.ref slot-spec 'combiner))
        (meet-fn (.ref slot-spec 'meet-fn)))
    (case combiner
      ((exclusive) higher-val)
      ((union) (list-dedup-union lower-val higher-val))
      ((refine) (refine-poo-objects lower-val higher-val))
      ((meet)
       (let ((fn (or meet-fn governance-envelope-meet)))
         (fn lower-val higher-val)))
      (else higher-val))))

;; Merge a list of (source-id . value) contributions belonging to the SAME C4 band.
;; Returns (values ok? combined-val diagnostics).
(def (merge-band-contributions module-id slot-spec entries)
  (cond
   ((null? entries) (values #t #f '()))
   ((null? (cdr entries)) (values #t (cdr (car entries)) '()))
   (else
    (let loop ((rest (cdr entries))
               (acc-src (car (car entries)))
               (acc-val (cdr (car entries)))
               (diags '()))
      (if (null? rest)
        (values (null? diags) acc-val (reverse diags))
        (let ((next-src (car (car rest)))
              (next-val (cdr (car rest))))
          (let-values (((ok? merged diag)
                        (combine-peer-values module-id slot-spec acc-src acc-val next-src next-val)))
            (if ok?
              (loop (cdr rest) acc-src merged diags)
              (loop (cdr rest) acc-src acc-val (cons diag diags))))))))))
