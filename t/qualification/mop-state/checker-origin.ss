;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification only: inspect identity/ownership without executing a checker.
;;; This is not an unforgeable producer certificate or a production MOP change.
(import :clan/poo/object
        (prefix-in (only-in :gerbil/runtime/mop object-class slot-ref) runtime.)
        (only-in :clan/poo/mop make-slot-read slot-read-receiver slot-read-key
                 slot-read-dependencies call-with-slot-read-observer))
(export recorded require-owned-reads!)
(def record-class (runtime.object-class (make-slot-read #f #f 0 #f #f '() values)))
(def (recorded action)
  (def reads '())
  (call-with-slot-read-observer (lambda (read) (set! reads (cons read reads))) action)
  (reverse reads))
(def (require-owned-reads! roots)
  (def seen (make-hash-table-eq))
  (def (visit read)
    (unless (hash-key? seen read)
      (unless (eq? (runtime.object-class read) record-class)
        (error "foreign slot-read type"))
      (unless (eq? (runtime.slot-ref read 'current?) object-read-current?)
        (error "foreign slot-read checker"))
      (let ((receiver (slot-read-receiver read)) (key (slot-read-key read)))
        (unless (and (object? receiver) (object-%reads receiver)
                     (eq? read (hash-get (object-%reads receiver) key)))
          (error "unowned slot-read record")))
      (hash-put! seen read #t)
      (for-each visit (slot-read-dependencies read))))
  (for-each visit roots)
  #t)
