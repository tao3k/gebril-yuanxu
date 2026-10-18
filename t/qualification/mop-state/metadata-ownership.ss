;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Isolation experiment, NOT a production write barrier. SDK raw writes bypass it.
(import :clan/poo/object
        (only-in :clan/poo/slot-observation slot-read-receiver slot-read-dependencies)
        (prefix-in (only-in :gerbil/runtime/mop slot-ref slot-set!) runtime.))
(export call-with-owned-metadata metadata-set!)
;; Private association; callers supply genuine reads, never owner labels.
(def metadata-frames (make-parameter '()))
(def (call-with-owned-metadata roots observe)
  (def owners (make-hash-table-eq))
  (def seen (make-hash-table-eq))
  (def (associate target owner)
    (when target
      (let (prior (or (hash-get owners target) '()))
        (unless (memq owner prior)
          (hash-put! owners target (cons owner prior))))))
  (def (table target owner)
    (when target
      (associate target owner)
      (associate (runtime.slot-ref target 'object) owner)))
  (def (visit read)
    (unless (hash-key? seen read)
      (unless (object-read-issued? read) (error "unissued slot dependency"))
      (hash-put! seen read #t)
      (let (owner (slot-read-receiver read))
        (associate owner owner)
        (associate read owner)
        (associate (object-%state owner) owner)
        (table (object-%reads owner) owner)
        (table (object-%instance owner) owner))
      (for-each visit (slot-read-dependencies read))))
  (for-each visit roots)
  (parameterize ((metadata-frames (cons owners (metadata-frames))))
    (replay-slot-reads! roots observe)))
;; One proposed mutation gateway, shared by every field/record/table operation.
;; This prototype exercises pre-write checking, NOT cache repair for allowed writes.
(def (metadata-set! target slot value)
  (def found? #f)
  (for-each
    (lambda (owners)
      (let (associated (hash-get owners target))
        (when associated
          (set! found? #t)
          (for-each
            (lambda (owner) (check-object-edit owner (object-%state owner)))
            associated))))
    (metadata-frames))
  (unless found? (error "unowned metadata write"))
  (runtime.slot-set! target slot value))
