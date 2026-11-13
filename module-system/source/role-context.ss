;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Transfer Gerbil-owned role contexts; selection and admission stay local.
(import (only-in :clan/poo/object .ref))
(export transfer-role-context)

;; visit walks Gerbil's actual import graph. support exposes only the reader's
;; recorded source association, not preparations or old selection guards.
;; No destination context is installed before the complete support is checked.
(def (transfer-role-context context visit support resolve-owner tool? available? install! refuse)
  (and context
    (let ((rows '()) (compatible? #t))
      (visit context
        (lambda (child)
          (let-values (((input owner assets initialization-current!) (support child)))
            (cond
             ((and input owner initialization-current!)
              (let (resolved (resolve-owner (.ref input 'path)))
                (unless (equal? owner resolved)
                  (refuse (list 'rebound owner resolved))
                  (set! compatible? #f))
                (set! rows (cons (list child input owner assets initialization-current!) rows))))
             ;; Canonical imports are authenticated by the receiving reader's
             ;; existing compiler-tool path, including its captured identity.
             ((tool? child) (void))
             (else (refuse (list 'unowned child)) (set! compatible? #f))))))
      (and compatible?
        (with-catch (lambda (_stale) (refuse 'source-changed) #f)
          (lambda ()
            (for-each
              (lambda (row)
                ((list-ref row 4))
                ((.ref (cadr row) 'admit-current))
                (for-each (lambda (input)
                            (resolve-owner (.ref input 'path))
                            ((.ref input 'admit-current)))
                          (cadddr row))) rows)
            #t))
        ;; Source guards can run callbacks. Check destination bindings after
        ;; those callbacks and before installing any private context.
        (andmap (lambda (row)
                  (let (path (.ref (cadr row) 'path))
                    (or (available? path (car row))
                        (begin (refuse (list 'context-conflict path)) #f))))
                rows)
        (begin
          (for-each (lambda (row) (apply install! row)) (reverse rows))
          context)))))
