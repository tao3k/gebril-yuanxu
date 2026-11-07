;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source preparation shared by publication suites; no test suite is imported.
(import (only-in :std/test test-suite check-equal?)
        (only-in :clan/poo/object .o .get replay-slot-reads!)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads
                 call-with-slot-read-observer slot-read-key slot-read-receiver)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        (only-in :yuanxu/module-system/source/reader call-with-publication-reads)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/t/qualification/module-publication/controls
                 register-reader-root-collection-cases!))
(export reader-root-collection-test)
(def reader-root-collection-test
  (test-suite "Selected publication controls"
    (yuanxu-test-case "native child capture merges original roots before finish without redelivery"
      (def before (.o value: 'before))
      (def child (.o value: 'child))
      (def after (.o value: 'after))
      (for-each (lambda (value) (.get value value)) (list before child after))
      (check-equal? (call-with-publication-reads owned-read-function-scope?) #t)
      (def events '())
      (def captured '())
      (defvalues (result roots)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-slot-read-observer
              (lambda (read)
                (when (eq? (slot-read-key read) 'value)
                  (set! events (cons (slot-read-receiver read) events))))
              (lambda ()
                (.get before value)
                (call-with-publication-reads
                  (lambda ()
                    ;; The external observer remains installed in the child.
                    (check-equal? (owned-read-function-scope?) #f)
                    (.get child value)
                    (.get child value))
                  (lambda (values current! original)
                    (set! captured original)
                    (current!)
                    (.get after value)
                    values)))))))
      (def values (filter (lambda (read) (eq? (slot-read-key read) 'value)) roots))
      (check-equal? result 'child)
      (check-equal? (map slot-read-receiver values) (list before child after))
      (check-equal? (reverse events) (list before child child after))
      (check-equal? (eq? (car captured) (cadr values)) #t)
      (replay-slot-reads! roots void)
      (defvalues (_value occurrences)
        (%call-with-recorded-slot-reads
          (lambda ()
            (call-with-publication-reads
              (lambda () (.get child value) (.get child value)) #f unique-roots?: #f))))
      (check-equal? (length (filter (lambda (read) (eq? (slot-read-key read) 'value)) occurrences)) 2))
    (yuanxu-test-case "failed child action and projection retain partial issued roots"
      (def child (.o value: 'child))
      (.get child value)
      (for-each
        (lambda (phase)
          (def original (gensym phase))
          (def finished? #f)
          (defvalues (caught roots)
            (%call-with-recorded-slot-reads
              (lambda ()
                (parameterize
                  ((current-module-source-observer
                    (and (eq? phase 'projection)
                      (lambda (key _amount)
                        (when (equal? key '(reader-projection-start body)) (raise original))))))
                  (with-catch identity
                    (lambda ()
                      (call-with-publication-reads
                        (lambda ()
                          (.get child value)
                          (when (eq? phase 'action) (raise original)))
                        (lambda (values _current! _roots) (set! finished? #t) values))))))))
          (check-equal? (eq? caught original) #t)
          (check-equal? finished? #f)
          (check-equal? (length (filter (lambda (read) (eq? (slot-read-key read) 'value)) roots)) 1)
          (replay-slot-reads! roots void))
        '(action projection)))
    (register-reader-root-collection-cases!)))
