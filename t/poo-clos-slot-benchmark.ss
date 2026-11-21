;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Hot bound-slot access witness; the CLOS lifecycle remains authoritative.

(import (only-in :gerbil/runtime/gambit current-jiffy jiffies-per-second)
        (only-in :clan/poo/mop clos-class clos-direct-slot-definition
                 clos-make-instance clos-set-slot-value! clos-slot-value))

(def +iterations+ 100000)
(def class-value
  (clos-class
   'slot-benchmark
   direct-slots: (list (clos-direct-slot-definition 'value))))
(def instance-value (clos-make-instance class-value))
(clos-set-slot-value! instance-value 'value 42)

(def (measure label thunk expected)
  (unless (= (thunk) expected)
    (error "slot benchmark semantic mismatch" label))
  (let warm ((index 0))
    (when (< index 1000)
      (thunk)
      (warm (+ index 1))))
  (let ((start (current-jiffy)))
    (let run ((index 0) (last #f))
      (if (= index +iterations+)
        (begin
          (unless (= last expected)
            (error "slot benchmark result drift" label))
          (display label) (display "-ms-per-1000=")
          (display
           (/ (* (- (current-jiffy) start) 1000000)
              (* (jiffies-per-second) +iterations+)))
          (newline))
        (run (+ index 1) (thunk))))))

(display "schema=core.poo-clos-slot.v1\n")
(display "iterations=") (display +iterations+) (newline)
(measure "bound-read" (lambda () (clos-slot-value instance-value 'value)) 42)
(measure "bound-write"
         (lambda () (clos-set-slot-value! instance-value 'value 42)) 42)
(display "accepted=#t\n")
