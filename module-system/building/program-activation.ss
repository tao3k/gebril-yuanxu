;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
(export program-activation-form)

;; Reuse Gerbil's registry and synchronization, including its compiler-selected
;; unchecked entry. Rebinding only load-module leaves optimized callers behind.
(def (program-activation-form linked aliases)
  `(let ((original-module __load-module) (linked ',linked) (aliases ',aliases))
     (define (complete! module state result)
       (mutex-lock! __load-mx)
       (hash-put! __modules module state)
       (when (and (string? state) (not (hash-get __load-order module)))
         (hash-put! __load-order module __load-order-next)
         (set! __load-order-next (+ __load-order-next 1)))
       (condition-variable-broadcast! __load-cv)
       (mutex-unlock! __load-mx)
       result)
     (define (activate entry module)
       (mutex-lock! __load-mx)
       (let ((state (hash-get __modules module)))
         (cond
           ((or (eq? state 'builtin) (string? state))
            (mutex-unlock! __load-mx)
            state)
           ((eq? state 'loading)
            (mutex-unlock! __load-mx __load-cv)
            (activate entry module))
           ((and (pair? state) (eq? (car state) 'error))
            (mutex-unlock! __load-mx)
            (raise (cadr state)))
           (state
            (mutex-unlock! __load-mx)
            (error "unexpected program activation state" module state))
           (else
            (hash-put! __modules module 'loading)
            (mutex-unlock! __load-mx)
            (with-catch
              (lambda (failure)
                (complete! module (list 'error failure) #f)
                (raise failure))
              (lambda ()
                (for-each load-module (cadddr entry))
                (when (cadr entry) (##load-module (cadr entry)))
                (complete! module (caddr entry) (caddr entry))))))))
     (set! __load-module
       (lambda (module)
         (let* ((alias (assoc module aliases))
                (entry (or (assoc module linked)
                           (and alias (assoc (cdr alias) linked)))))
           ;; Both Gerbil spellings share initialization and its outcome.
           (if entry
               (activate entry (car entry))
               (original-module module)))))
     (set! load-module
       (lambda (module)
         (unless (string? module) (error "expected a module path" module))
         (__load-module module)))))
