;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source-bound admission is above the pure Contract kernel, not a Loader.
(import :clan/poo/object
        (only-in :clan/poo/mop define-type call-with-slot-read-observer replay-slot-reads!)
        (only-in :clan/poo/object-contract diagnose)
        (only-in :clan/poo/object-diagnostics diagnostic-then)
        (only-in :yuanxu/object-types/contracts YuanxuContract. yuanxu-classification-evidence
                 yuanxu-validation-evidence call-with-contract-analysis-root)
        (only-in :yuanxu/configuration/slot-origin admit-field-sources!)
        (only-in :yuanxu/module-system/source/admission
                 module-source-admit-current! call-with-module-source-read-cache
                 call-with-module-source-fresh-reads call-with-collected-module-sources
                 current-module-source-phase))
(export SourceAdmissionContract. source-diagnose-at call-with-source-slot-reads)

;; Consume MOP observations; the object engine owns recording and cache replay.
;; Before-read checks protect cold getters too. Return-time replay must not reuse
;; a previous source-currentness decision or a manually enumerated leaf catalog.
(def (call-with-source-slot-reads action)
  (def roots (make-hash-table-eq))
  (def (check-source receiver key)
    (cond
      ((symbol? key) (admit-field-sources! receiver (list (list key))))
      ((memq (car key) '(presence cache-miss bootstrap))
       (admit-field-sources! receiver (list (list (cadr key)))))))
  (def (observe read)
    ;; Actual demands check sources before reads. Replay the shared graph ONCE
    ;; before return, rather than walking every transitive prefix on every hit.
    (hash-put! roots read #t))
  (def result (call-with-slot-read-observer observe action before: check-source))
  ;; Replay checks only recorded one-slot source metadata: it cannot execute a
  ;; getter or a Contract obligation. Share bytes within this pure pass only.
  ;; Start fresh even inside an enclosing validation window; never carry this
  ;; cache across action, nested admission, or the independent return check.
  (parameterize ((current-module-source-phase 'slot-replay))
    (call-with-module-source-fresh-reads
      (lambda ()
        (call-with-module-source-read-cache
          (cut replay-slot-reads! (hash-keys roots) check-source)))))
  result)

;; Domain-owned stages run inside SourceAdmissionContract's MOP observer.
;; Contract reads discover leaves; do not maintain another source path list.
(def (source-diagnose-at constraint path)
  (lambda (candidate location)
    (diagnose constraint
      (foldl (lambda (name value) (.ref value name)) candidate path)
      (append location path))))

(def (source-contract-admit contract next candidate context)
  (def (sources-current!)
    (module-source-admit-current! (.get contract source-inputs)
      "configuration source changed"))
  (sources-current!)
  (def failures ((.get contract prepared-preflight) candidate '()))
  (def evidence
    (if (null? failures)
      ;; The inherited kernel includes arbitrary obligations. Do not keep a
      ;; source-byte window open across their calls or nested admissions.
      (call-with-contract-analysis-root contract candidate context
        (cut next candidate context))
      (let (classification
             (yuanxu-classification-evidence
               (.get contract identity) candidate #f failures context))
        (yuanxu-validation-evidence
          contract candidate classification '() #f failures context))))
  ;; Decoration sees original slot specifications; the receipt still describes
  ;; the normalized candidate and retains exact contextual child receipts.
  (def (locate failures)
    (map (cut (.get contract .locate-diagnostic) candidate <>) failures))
  ;; Complete locator checks inside collection, before the final replay.
  ;; Native .cc receives these eagerly evaluated values, not deferred hooks.
  (def classification-issues (locate (.get evidence classification diagnostics)))
  (def issues (locate (.get evidence diagnostics)))
  (def result
    (.cc evidence
      classification: (.cc (.get evidence classification) diagnostics: classification-issues)
      diagnostics: issues))
  ;; This protocol slot is replaceable: do not classify it as a pure inspector
  ;; or carry its source bytes into the independent final collector check.
  (when (and (null? failures) (object? context) (.slot? context 'admit-current))
    ((.get context admit-current)))
  (sources-current!)
  result)

(define-type (SourceAdmissionContract. @ YuanxuContract.
               source-inputs .preflight .locate-diagnostic value-contract)
  source-inputs: '()
  .preflight: (lambda (_candidate _path) '())
  .locate-diagnostic: (lambda (_candidate diagnostic) diagnostic)
  ;; Field-demand guards precede the native whole-value diagnosis. Recognition
  ;; does not normalize; the inherited producer still validates exactly once.
  ;; Cache the COMPOSITION on this receiver, never a successful admission.
  prepared-preflight:
  (diagnostic-then .preflight
    (if value-contract (cut diagnose value-contract <> <>)
      (lambda (_candidate _path) '())))
  (.admit (inherited)
    (lambda (candidate context)
      (call-with-module-source-fresh-reads
        (lambda ()
          (call-with-collected-module-sources
            (lambda (sources-current!)
              (def evidence
                (call-with-source-slot-reads
                  (cut source-contract-admit @ (inherited) candidate context)))
              (parameterize ((current-module-source-phase 'return-currentness))
                (sources-current!))
              evidence)))))))
