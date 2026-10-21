;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Call-local retention projection; native MOP still owns read validity.
(import (only-in :clan/poo/object .all-slots object? object-%precedence-list object-protocol replay-slot-reads!
                 object-revision object-supers object-%protocol object-%declarations)
        (only-in :clan/poo/slot-observation
                 %call-with-recorded-slot-reads %deliver-slot-read slot-read-value
                 slot-read-receiver slot-read-dependencies
                 call-with-slot-read-observer))
(export call-with-owned-read-projection current-owned-read-open-guard owned-read-value! owned-read-leaf! owned-read-copy! owned-read-derived! owned-read-open!
        owned-read-method! owned-read-hook-owner!)

;; This region is a construction/ownership scope, never a result/currentness
;; cache. It is released when the call returns. Only Core constructors enroll
;; receivers; ancestry or a user-supplied kind cannot claim ownership.
(defstruct read-region (bodies owned parents open?) final: #t)
(def current-region (make-parameter #f))
;; An operation owner may require a fresh boundary BEFORE a known open call.
;; No approval is retained; the owner decides the support and sticky fallback.
(def current-owned-read-open-guard (make-parameter #f))
(def (owned-read-value! receiver)
  (when (current-region)
    ;; Keep the FIRST native generation, including mutate-and-restore edits.
    (unless (hash-key? (read-region-owned (current-region)) receiver)
      (hash-put! (read-region-owned (current-region)) receiver (object-revision receiver))))
  receiver)
(def (owned-read-leaf! receiver)
  ;; Only audited bare Core factories use this path. No parent, declaration or
  ;; protocol can hide a shared currentness requirement outside native reads.
  (when (current-region)
    (unless (and (null? (object-supers receiver))
                 (not (object-%protocol receiver))
                 (null? (object-%declarations receiver)))
      (owned-read-open!)))
  (owned-read-value! receiver))
(def (owned-read-derived! receiver)
  ;; Actual Core factory only. Keep the transitive parent policy, not the
  ;; temporary instance. Labels and nominal Types confer no enrollment right.
  (when (current-region)
    (let (parents (read-region-parents (current-region)))
      (def (visit parent)
        (unless (hash-key? parents parent)
          (hash-put! parents parent (object-revision parent))
          (.all-slots parent)
          (when (or (object-%protocol parent) (pair? (object-%declarations parent)))
            (owned-read-open!))
          (for-each visit (object-supers parent))))
      (when (or (object-%protocol receiver) (pair? (object-%declarations receiver)))
        (owned-read-open!))
      (for-each visit (object-supers receiver))))
  (owned-read-value! receiver))
(def (owned-read-copy! original copy)
  ;; A clone of a contributed/previous receipt is not a constructor capability.
  (when (current-region)
    (if (hash-key? (read-region-owned (current-region)) original)
      (owned-read-leaf! copy)
      (owned-read-open!)))
  copy)
(def (owned-read-open!)
  (when (current-owned-read-open-guard)
    (let (guard (current-owned-read-open-guard))
      (parameterize ((current-owned-read-open-guard #f)) (guard))))
  (when (current-region) (set! (read-region-open? (current-region)) #t)))
(def (owned-read-hook-owner! receiver)
  (when (current-region)
    ;; Inspect only an already demanded descriptor; never force a cold getter
    ;; to decide whether an unknown MOP hook should have been allowed.
    (unless (and (object? receiver) (object-%precedence-list receiver)
                 (not (object-protocol receiver)))
      (owned-read-open!))))
(def (owned-read-method! body receiver)
  (when (and (not (current-region)) (current-owned-read-open-guard))
    (owned-read-open!))
  (when (current-region)
    (owned-read-hook-owner! receiver)
    (unless (memq body (read-region-bodies (current-region))) (owned-read-open!))))
(def (observe-owned-hook read)
  ;; Inspect only an actually demanded receiver. Unknown native MOP execution
  ;; keeps the WHOLE trace; this neither suppresses nor stores observations.
  (owned-read-hook-owner! (slot-read-receiver read)))

(def (deliver-original-reads reads)
  ;; Preserve native issuer identity and first-delivery order. No reconstructed
  ;; checker, synthetic owner or weak witness may enter the native graph.
  (for-each
    (lambda (read)
      (%deliver-slot-read read (slot-read-value read))) reads))

(def (call-with-owned-read-projection bodies stable? action)
  (if (current-region)
    ;; Nested dispatch shares ownership; an unknown body opens the WHOLE region.
    (action)
    (let ((region (make-read-region bodies (make-hash-table-eq) (make-hash-table-eq) #f))
          (failed? #f) (failure #f))
      (defvalues (results reads)
        (%call-with-recorded-slot-reads
          (lambda ()
            (parameterize ((current-region region))
              (with-catch
                (lambda (exception)
                  (set! failed? #t) (set! failure exception) '())
                (lambda ()
                  (call-with-slot-read-observer observe-owned-hook
                    (lambda ()
                      ;; Native policy reads belong to this same recording frame.
                      (stable?)
                      (begin0 (call-with-values action list) (stable?))))))))
          unique-roots?: #t))
      ;; All paths retain the complete original graph. In particular, a failed
      ;; action must not erase its dependencies from an enclosing computation.
      (deliver-original-reads reads)
      ;; This is observation forwarding, not admission. With no weak projection
      ;; to certify, the enclosing native consumer owns replay at its existing
      ;; boundary; do not move a deferred refusal into the middle of an action.
      (if failed? (raise failure) (apply values results)))))
