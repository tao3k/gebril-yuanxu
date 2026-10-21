;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Qualification only: actual cold frames, replay callbacks and external files.
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop call-with-slot-read-observer replay-slot-reads!)
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/module-system/source/admission module-source-read current-module-source-observer)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture write-source))
(export mop-serial-use-test test-cleanup!)
(def completed 0)
(def (test-cleanup!)
  (check-equal? completed 4)
  (displayln "MOP-SERIAL-USE: 4 cases completed"))
(def (refuses message action)
  (def failure (with-catch values action))
  (check-equal? (Error? failure) #t)
  (check-equal? (Error-message failure) message))
(def (recorded action)
  (def roots '())
  (call-with-slot-read-observer (lambda (read) (set! roots (cons read roots))) action)
  (reverse roots))
(def mop-serial-use-test
 (test-suite "Serial computation boundaries are not external transactions"
  (yuanxu-test-case "cold receiver is protected; warm access does not rerun the body; return releases protection"
    (def calls 0)
    (.def Root
      port: 5432
      preview: (let ((before (object-revision Root)) (value (.get Root port)))
                 (set! calls (+ 1 calls))
                 (refuses "object mutation during computation"
                   (cut .putslot! Root 'port ($constant-slot-spec 9999)))
                 (check-equal? (object-revision Root) before)
                 value)
      unused: (error "unselected branch forced"))
    (def previous (active-slot-computations))
    (check-equal? (.get Root preview) 5432)
    (check-equal? (.get Root preview) 5432)
    (check-equal? calls 1)
    (check-equal? (eq? (active-slot-computations) previous) #t)
    (.putslot! Root 'port ($constant-slot-spec 5433))
    (check-equal? (.get Root preview) 5433)
    (check-equal? calls 2)
    (set! completed (+ completed 1)))
  (yuanxu-test-case "an external demand can change inside the same cold receiver computation"
    (.def Database port: 5432)
    (def captured #f)
    (.def Application
      preview: (let (value (.get Database port))
                 (set! captured value)
                 (.putslot! Database 'port ($constant-slot-spec 5433))
                 value))
    (def before (object-revision Application))
    (def roots (recorded (cut .get Application preview)))
    (check-equal? captured 5432)
    (check-equal? (.get Database port) 5433)
    (check-equal? (object-revision Application) before)
    (refuses "stale slot dependency"
      (cut replay-slot-reads! roots (lambda (_receiver _key) (void))))
    (set! completed (+ completed 1)))
  (yuanxu-test-case "a warm replay observer is refused before mutating its receiver"
    (.def Root port: 5432)
    (def roots (recorded (cut .get Root port)))
    (def calls 0)
    (refuses "object mutation during read replay"
      (lambda ()
        (replay-slot-reads! roots
          (lambda (_receiver _key)
            (set! calls (+ 1 calls))
            (.putslot! Root 'port ($constant-slot-spec 5433))))))
    (check-equal? calls 1)
    (check-equal? (.get Root port) 5432)
    (set! completed (+ completed 1)))
  (yuanxu-test-fixture "a cold MOP frame and restored dynamic observer do not fence a source file"
    (fixture DirectoryFixture)
    (def path (path-expand "input.json" (.get fixture root)))
    (write-source path "before")
    (def previous (current-module-source-observer))
    (def observed 0)
    (.def Root
      preview: (let (bytes (module-source-read path))
                 (parameterize ((current-module-source-observer
                                 (lambda (_key _amount) (set! observed (+ observed 1)))))
                   (write-source path "after")
                   (check-equal? (module-source-read path) "after"))
                 bytes))
    (check-equal? (.get Root preview) "before")
    (check-equal? (> observed 0) #t)
    (check-equal? (eq? (current-module-source-observer) previous) #t)
    (check-equal? (module-source-read path) "after")
    (set! completed (+ completed 1)))))
