;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: analyzes composition lineage for cycles and productive recursion.
;;; Invariant: analysis reports lineage facts without mutating the composed objects.
(import (only-in :yuanxu/object-family/syntax
                 defpoo-object-family)
        (only-in :std/list/list duplicates))

(export yuanxu-lineage-analysis-prototype
        yuanxu-lineage-cycle?
        yuanxu-productive-recursion?
        yuanxu-lineage-analysis
        yuanxu-lineage-analysis?)

;; : (-> [YuanxuLineageIdentity] Boolean)
(def (yuanxu-lineage-cycle? lineage)
  (if (pair? (duplicates lineage)) #t #f))

;; : (-> [YuanxuLineageIdentity] [YuanxuLineageIdentity] Boolean)
(def (yuanxu-productive-recursion? lineage productive-identities)
  (and (yuanxu-lineage-cycle? lineage)
       (let (productive-table (make-hash-table))
         (for-each
          (lambda (identity)
            (hash-put! productive-table identity #t))
          productive-identities)
         (if (any (lambda (identity)
                    (hash-key? productive-table identity))
                  lineage)
             #t
             #f))))

;; : (-> [YuanxuLineageIdentity] [YuanxuLineageIdentity] YuanxuLineageAnalysis)
(def (yuanxu-lineage-analysis-values lineage-value productive-identities)
  (let* ((cycle-value (yuanxu-lineage-cycle? lineage-value))
         (productive-value
          (yuanxu-productive-recursion?
           lineage-value productive-identities))
         (status-value
          (match (cons cycle-value productive-value)
            ([#f . _] 'acyclic)
            ([#t . #t] 'productive-recursion)
            (else 'non-productive-cycle))))
    (values lineage-value cycle-value productive-value status-value)))

(defpoo-object-family
  (prototype yuanxu-lineage-analysis-prototype
             lineage-analysis?
             yuanxu-lineage-analysis?
             (kind 'lineage-analysis))
  (constructor make-yuanxu-lineage-analysis
               (lineage-value lineage)
               (cycle-value cycle?)
               (productive-value productive?)
               (status-value status))
  (accessors)
  (projections))

;; : (-> [YuanxuLineageIdentity] [YuanxuLineageIdentity] YuanxuLineageAnalysis)
(def (yuanxu-lineage-analysis lineage-value productive-identities)
  (call-with-values
   (lambda ()
     (yuanxu-lineage-analysis-values lineage-value productive-identities))
   make-yuanxu-lineage-analysis))
