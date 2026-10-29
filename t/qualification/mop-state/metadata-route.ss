;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification only: use the producer's actual selected metadata route.
(import :clan/poo/object
        (prefix-in (only-in :gerbil/runtime/mop object-class slot-ref) runtime.)
        (prefix-in (only-in :clan/poo/read-route require-read-route!) producer.)
        (only-in :clan/poo/mop make-slot-read slot-read-receiver slot-read-key))
(export require-read-route! guarded-current?)
(def record-class (runtime.object-class (make-slot-read #f #f 0 #f #f '() values)))
(def (require-read-route! read)
  (unless (eq? (runtime.object-class read) record-class) (error "foreign slot-read type"))
  (unless (eq? (runtime.slot-ref read 'current?) object-read-current?)
    (error "foreign slot-read checker"))
  (def receiver (slot-read-receiver read))
  (unless (object? receiver) (error "unsupported metadata receiver"))
  ;; The producer handles both vector instances and symbolic hash controls,
  ;; including the vector shape's index route, without invoking table methods.
  (producer.require-read-route! (slot-read-key read)
    (object-%reads receiver) (object-%instance receiver))
  #t)
(def (guarded-current? read)
  (require-read-route! read)
  ;; Route validity is not issuance. Preserve the original credential check.
  (object-read-current? read))
