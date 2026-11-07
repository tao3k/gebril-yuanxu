;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Exercise the producer's route guard; do not duplicate its storage model.
(import :clan/poo/object
        (rename-in (only-in :clan/poo/read-route require-read-route!)
                   (require-read-route! producer-require-read-route!))
        (only-in :clan/poo/slot-observation slot-read-receiver slot-read-key))
(export require-read-route! guarded-current?)

(def (require-read-route! read)
  (def receiver (slot-read-receiver read))
  (producer-require-read-route! (slot-read-key read)
    (object-%reads receiver) (object-%instance receiver))
  #t)

(def (guarded-current? read)
  (require-read-route! read)
  (object-read-current? read))
