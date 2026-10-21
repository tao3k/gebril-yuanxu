;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Native VM positive control before any Case watchdog has been terminated.
(import :std/test :clan/poo/object
        (only-in :yuanxu/observability/memory yuanxu-debug-memory-snapshot))
(export raw-allocation-test)

(def raw-allocation-test
  (test-suite "Fresh native allocation counter"
    (test-case "nearby raw samples include the live allocated payload"
      (def before (yuanxu-debug-memory-snapshot 'before))
      (def payload (make-u8vector 65536 0))
      (def after (yuanxu-debug-memory-snapshot 'after))
      (check-equal? (u8vector-length payload) 65536)
      (check-equal? (>= (- (.get after allocated-bytes)
                          (.get before allocated-bytes)) 65536) #t))))
