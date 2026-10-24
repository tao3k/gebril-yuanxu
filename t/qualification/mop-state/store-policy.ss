;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Isolation compiler policy. No public replacement mutation API.
(import :clan/poo/object
        (prefix-in (only-in :gerbil/runtime/mop find-method bind-method! slot-ref) runtime.))
(export before-store! specification-owners register-allocation! store-frame-depth)
;; Qualification-only access to the CURRENT producer's PRIVATE native frame.
;; Production integration belongs inside object.ss, without this extern bridge.
(extern namespace: clan/poo/object active-read-replays)
(def direct-owners (make-hash-table test: eq? weak-keys: #t))
(def (store-frame-depth) (length (active-read-replays)))
;; The native initializer supplies identities for EVERY constructor route,
;; including .cc/direct metadata copies which have no ancestry edge to SELF.
(def original-init (runtime.find-method object::t #f ':init!))
(def (register-allocation! self)
  (for-each
    (lambda (entry)
      (def spec (cdr entry))
      (def owners (or (hash-get direct-owners spec)
        (let (table (make-hash-table test: eq? weak-keys: #t))
          (hash-put! direct-owners spec table) table)))
      (hash-put! owners self #t))
    (object-slots self)))
(def (tracked-init self . args)
  (def result (apply original-init self args))
  (register-allocation! self)
  result)
(runtime.bind-method! object::t ':init! tracked-init #t)

;; A diagnostic query, not a full-graph scan at each read/store. Descendants
;; come from the native constructor's existing weak dependency edges.
(def (specification-owners spec)
  (def seen (make-hash-table-eq))
  (def result '())
  (def (visit owner)
    (unless (hash-key? seen owner)
      (hash-put! seen owner #t)
      (set! result (cons owner result))
      (let (children (runtime.slot-ref (object-%state owner) 'dependents))
        (when children
          (for-each (lambda (entry) (visit (car entry))) (hash->list children))))))
  (let (owners (hash-get direct-owners spec))
    (when owners (for-each (lambda (entry) (visit (car entry))) (hash->list owners))))
  result)

;; Called automatically from lowered native structure stores. The actual
;; receiver guard still owns the diagnostic and dynamic replay protection.
(def (before-store! target)
  (when (pair? (active-read-replays))
    (when ($slot-spec? target)
      (unless (hash-get direct-owners target)
        (error "unregistered specification allocation"))
      ;; Read-only preflight of ALL native registered users, including copies
      ;; without a parent edge. No invalidation or revision change occurs here.
      (for-each
        (lambda (owner) (check-object-edit owner (object-%state owner)))
        (specification-owners target)))))

;; The derived SDK bodies are generated/compiled from the ACTIVE SDK, not .data.
(let (root (getenv "CORE_STORE_ROOT" #f))
  (unless root (error "missing isolated store compilation root"))
  (load (path-expand "store-runtime.o1" root)))
