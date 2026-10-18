;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Isolation compiler policy. No public replacement mutation API.
(import :clan/poo/object
        (only-in :clan/poo/slot-observation slot-read-receiver slot-read-key slot-read-dependencies)
        (prefix-in (only-in :gerbil/runtime/mop find-method bind-method! slot-ref) runtime.))
(export call-with-selected-stores before-store! specification-owners register-allocation!)
(def direct-owners (make-hash-table test: eq? weak-keys: #t))
(def selected-stores (make-parameter '()))
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
    (append (object-slots self) (object-defaults self))))
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

(def (call-with-selected-stores roots observe)
  (def targets (make-hash-table-eq))
  (def reads (make-hash-table-eq))
  (def (associate spec declarer receiver)
    (def registered (hash-get direct-owners spec))
    (unless (and registered (hash-key? registered declarer))
      (error "unregistered specification allocation"))
    (def previous (or (hash-get targets spec) '()))
    (unless (memq receiver previous)
      (hash-put! targets spec (cons receiver previous))))
  (def (carriers receiver key)
    (def seen (make-hash-table-eq))
    (def (visit owner)
      (unless (hash-key? seen owner)
        (hash-put! seen owner #t)
        (for-each
          (lambda (entry)
            (when (eq? key (car entry)) (associate (cdr entry) owner receiver)))
          (append (object-slots owner) (object-defaults owner)))
        (for-each visit (object-supers owner))))
    (visit receiver))
  (def (visit read)
    (unless (hash-key? reads read)
      (unless (object-read-issued? read) (error "unissued slot dependency"))
      (hash-put! reads read #t)
      (when (symbol? (slot-read-key read))
        (carriers (slot-read-receiver read) (slot-read-key read)))
      (for-each visit (slot-read-dependencies read))))
  (for-each visit roots)
  (parameterize ((selected-stores (cons targets (selected-stores))))
    (replay-slot-reads! roots observe)))

;; Called automatically from lowered native structure stores. The actual
;; receiver guard still owns the diagnostic and dynamic replay protection.
(def (before-store! target)
  (for-each
    (lambda (targets)
      (let (receivers (hash-get targets target))
        (when receivers
          (for-each
            (lambda (receiver) (check-object-edit receiver (object-%state receiver)))
            receivers))))
    (selected-stores)))

;; The derived SDK bodies are generated/compiled from the ACTIVE SDK, not .data.
(let (root (getenv "CORE_STORE_ROOT" #f))
  (unless root (error "missing isolated store compilation root"))
  (load (path-expand "store-runtime.o1" root)))
