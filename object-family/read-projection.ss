;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Call-local retention projection; MOP still owns read validity.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/prototype-map prototype-map-length)
        (only-in :clan/poo/slot-observation
                 %call-with-recorded-slot-reads %record-slot-reads!
                 slot-read-receiver slot-read-dependencies slot-read-key slot-read-value
                 call-with-slot-read-observer slot-read-observers-compatible?
                 slot-read-precheck-active?))
(export call-with-owned-read-projection current-owned-read-open-guard owned-read-value! owned-read-leaf! owned-read-copy! owned-read-derived! owned-read-open!
        owned-read-method! owned-read-hook-owner! owned-read-function-scope?
        make-owned-method-check call-with-owned-read-method-checks
        owned-read-fields-present? call-with-owned-source-reads)

;; This region is a construction/ownership scope, never a result/currentness
;; cache. It is released when the call returns. Only Core constructors enroll
;; receivers; ancestry or a user-supplied kind cannot claim ownership.
(defstruct read-region (bodies owned parents open?) final: #t)
(def current-region (make-parameter #f))
(defstruct owned-method-check (receiver key method) final: #t)
(def current-owned-method-checks (make-parameter '()))
;; An operation owner may require a fresh boundary BEFORE a known open call.
;; No approval is retained; the owner decides the support and sticky fallback.
(def current-owned-read-open-guard (make-parameter #f))
(def (owned-read-value! receiver)
  (when (current-region)
    ;; Keep the FIRST runtime generation, including mutate-and-restore edits.
    (unless (hash-key? (read-region-owned (current-region)) receiver)
      (hash-put! (read-region-owned (current-region)) receiver (object-revision receiver))))
  receiver)
(def (owned-read-leaf! receiver)
  ;; Only audited bare Core factories use this path. No parent, declaration or
  ;; protocol can hide a shared currentness requirement outside runtime reads.
  (when (current-region)
    (unless (and (null? (object-supers receiver))
                 (not (object-%protocol receiver))
                 (zero? (prototype-map-length (object-%declarations receiver))))
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
          (when (or (object-%protocol parent)
                    (positive? (prototype-map-length (object-%declarations parent))))
            (owned-read-open!))
          (for-each visit (object-supers parent))))
      (when (or (object-%protocol receiver)
                (positive? (prototype-map-length (object-%declarations receiver))))
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
(def (call-with-owned-read-method-checks checks action value)
  ;; The caller knows the delegated native operation. Check its actual read,
  ;; so an earlier shape rejection cannot open the boundary prematurely.
  (if (current-region)
    (parameterize ((current-owned-method-checks checks)) (action value))
    (action value)))
(def (observe-owned-hook read)
  ;; Inspect only an actually demanded receiver. Unknown MOP execution
  ;; keeps the WHOLE trace; this neither suppresses nor stores observations.
  (def receiver (slot-read-receiver read))
  (owned-read-hook-owner! receiver)
  (let (checks (current-owned-method-checks))
    (unless (null? checks)
      (let (key (slot-read-key read))
        (when (ormap (lambda (check)
                       (let (owner (owned-method-check-receiver check))
                         (and (eq? key (owned-method-check-key check))
                              (or (not owner) (eq? receiver owner))
                              (not (eq? (slot-read-value read)
                                        (owned-method-check-method check))))))
                     checks)
          (owned-read-open!))))))

;; One maintained precheck, with a private dynamic stack of actual Reader
;; boundaries. Nested callers cannot replace an enclosing Reader's boundary.
;; This replaces per-Reader callback closures; it is not a purity registry.
(def source-read-boundaries (make-parameter '()))
(def (before-owned-source-read receiver _key)
  (when (object? receiver)
    ;; A public C3 query now copies its spine. This guard only needs runtime
    ;; preparation; a warm canonical cache already follows the same no-hook
    ;; branch. Invalidation restores the ordinary cold preparation/refusal.
    (unless (object-%precedence-list receiver)
      (compute-precedence-list! receiver))
    (when (object-protocol receiver)
      (for-each (lambda (boundary) (boundary)) (source-read-boundaries)))))
(def (call-with-owned-source-reads boundary action)
  ;; without-observation may deliberately disable an outer runtime scope.
  ;; Reinstall only the new Reader there; do not resurrect disabled callbacks.
  (def enclosing (if (slot-read-precheck-active? before-owned-source-read)
                   (source-read-boundaries) '()))
  (parameterize ((source-read-boundaries (cons boundary enclosing)))
    (if (pair? enclosing) (action)
      (call-with-slot-read-observer void action before: before-owned-source-read))))

;; Actual runtime scope identities, never a Profile purity flag. The two
;; maintained observers only inspect ownership or discard delivery. Unknown
;; observers/prechecks keep ordinary dispatch. The maintained source precheck
;; remains ACTIVE on every actual read; it has no callback for hook-free runtime
;; carriers. A prior open callback does not
;; certify OR prohibit a later call: the caller freshly authenticates its live
;; declaration support. The region still retains and forwards its WHOLE trace.
(def (owned-read-function-scope?)
  (slot-read-observers-compatible? (list void observe-owned-hook)
                                 (list before-owned-source-read)))

;; One actual runtime inventory for a fresh factory receipt, not six separate
;; presence records retaining that receipt/instance/specification environment.
;; Public/contributed values, open callbacks and an already exposed inventory
;; retain the ordinary query path. The inventory is NEVER an admission result.
(def (owned-read-fields-present? receiver fields)
  (let* ((region (current-region))
         (revision (and region (hash-get (read-region-owned region) receiver))))
    (if (and revision (not (read-region-open? region))
             (owned-read-function-scope?)
             (= revision (object-revision receiver))
             (not (object-%all-slots receiver)))
      (let (names (.all-slots receiver))
        (and (andmap (cut memq <> names) fields) #t))
      (andmap (cut .slot? receiver <>) fields))))

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
                      ;; Runtime policy reads belong to this same recording frame.
                      (stable?)
                      (begin0 (call-with-values action list) (stable?))))))))
          unique-roots?: #t))
      ;; All paths retain the complete original graph. In particular, a failed
      ;; action must not erase its dependencies from an enclosing computation.
      ;; The native child capture inherited observers and already delivered
      ;; every actual read. Merge the original tokens into the parent frame;
      ;; redelivery would run those callbacks a second time. The parent keeps
      ;; its own occurrence policy and every token's signed dependency graph.
      (%record-slot-reads! reads)
      ;; This is observation forwarding, not admission. With no weak projection
      ;; to certify, the enclosing runtime consumer owns replay at its existing
      ;; boundary; do not move a deferred refusal into the middle of an action.
      (if failed? (raise failure) (apply values results)))))
