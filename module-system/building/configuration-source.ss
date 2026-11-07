;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Explicit build-tool evaluation of an observed role, not a Module Loader.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/slot-observation without-observation)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-admit-current! call-with-module-source-read-cache
                 current-module-source-phase current-module-source-observer module-source-object-policy
                 call-with-module-source-callback)
        (only-in :yuanxu/module-system/source/link linked-configuration-guard-active?)
        (only-in :yuanxu/module-system/source/reader module-prepared-source-binding))
(export yuanxu-configuration-source configuration-request-current/owned)
(defstruct configuration-request-check (context invoke closed ready?) final: #t)

;; The actual request must still publish the exact ordinary guard paired by
;; the configuration reader. Only the linker may invoke the closed half.
(def (configuration-request-current/owned check context invoke)
  (and (configuration-request-check? check)
       (eq? context (configuration-request-check-context check))
       (eq? invoke (configuration-request-check-invoke check))
       ((configuration-request-check-ready? check))
       (configuration-request-check-closed check)))
(def (yuanxu-configuration-source path binding context-current! role-sources: (roles '()) package-request?: (package-request? #f))
  (unless (and (symbol? binding) (eq? (module-source-type path) 'regular))
    (error "configuration source requires a regular role and runtime binding" path binding))
  (def phase (make-parameter #f))
  (def evaluated-inputs '())
  (def (admit-context!)
    (call-with-module-source-callback context-current!))
  (def (context!)
    (unless (phase) (admit-context!)))
  (def (with-checked-context thunk)
    (admit-context!)
    (parameterize ((phase #t)) (thunk)))
  (def source-checks '())
  (def (prepare-request-input file)
    ;; Capture the existing native source-only guard at its constructor.
    ;; The reader view still brackets imports/initializers with the original
    ;; Context callback. Only the private source checks can share a window.
    (call-with-module-source-callback context!)
    (yuanxu-prepare-module-build-source file void
      capture: (lambda (input check _path _ready? state)
                 (def intact? (object-construction-current?))
                 (def (admit!)
                   (call-with-module-source-callback context!)
                   ((.get input admit-current))
                   (call-with-module-source-callback context!))
                 (def view (.cc input admit-current: admit!))
                 (def policy (and intact? (object-construction-current?)
                                  (module-source-object-policy (list view))))
                 (set! source-checks
                   (cons (cons check
                           (and policy state
                                (lambda ()
                                  (and (policy) (state) (object-%instance view)
                                       (object-%precedence-list view)
                                       (begin
                                         (require-read-route! 'configuration-role #f (object-%instance view))
                                         (eq? admit! (.ref/cached view 'admit-current
                                                               (lambda () #f))))))))
                         source-checks))
                 view)))
  (def (prepare file)
    (if package-request? (prepare-request-input file)
      (yuanxu-prepare-module-build-source file void)))
  (def (source-checks-current?)
    (and (object-construction-current?) (not (current-module-source-observer)) (owned-read-function-scope?)
         (with-catch (lambda (_unsupported) #f)
           (lambda ()
             (without-observation
               (lambda ()
                 (andmap (lambda (row) (and (cdr row) ((cdr row)))) source-checks)))))))
  ;; Preparation and preflight precede import. Only the package request
  ;; owns the split checks; the ordinary reader keeps its Context callbacks.
  (def (prepare-related)
    (map prepare
         (filter (lambda (file)
                   (and (not (equal? path file))
                        (not (member (path-strip-directory file) '("interface.ss" "build.ss")))))
                 roles)))
  (let-values (((prepared related current!)
                (call-with-module-source-read-cache
                  (lambda ()
                    (defvalues (prepared related)
                      (if package-request?
                        (with-checked-context (lambda () (values (prepare path) (prepare-related))))
                        (values (prepare path) (prepare-related))))
                    (def (current! (site 'configuration-public))
                      (parameterize ((current-module-source-phase site))
                        (call-with-module-source-read-cache
                          (lambda ()
                            (with-checked-context
                              (lambda ()
                                (module-source-admit-current! evaluated-inputs)
                                ((.get prepared admit-current))
                                (for-each (lambda (input) ((.get input admit-current))) related)))))))
                    (current! 'configuration-pre-bootstrap)
                    (values prepared related current!)))))
    (set! source-checks (reverse source-checks))
    (let (effective (module-prepared-source-binding prepared binding related
                     context-current!: admit-context!
                     source-inputs: (lambda (inputs) (set! evaluated-inputs inputs))))
      ;; The reader checks prepared/related inputs AFTER runtime evaluation.
      ;; Its remaining work only releases completed private expansion results
      ;; and deletes its private wrapper directory. No author code or Nix lies
      ;; between that return check and this inert source projection. Keep the
      ;; pre-bootstrap check above and every later public current! call fresh.
      ;; Compiler support is guarded by current!, not serialized into a provider
      ;; package's configuration input. Keep those two dependency roles distinct.
      (def result
        (.o value: effective
            source-inputs: (append (.get prepared source-inputs)
                                   (foldr append '() (map (cut .get <> source-inputs) related)))
            admit-current: current!))
      (if (not package-request?) result
        (.cc result .request-check:
          (lambda (observations)
            ;; Keep the enrolled bytes private to the request.
            (def inputs (map (lambda (row)
                               (cons (string-copy (car row))
                                     (and (cdr row) (string-copy (cdr row)))))
                             observations))
            (def (ordinary!)
              (call-with-module-source-read-cache
                (lambda () (current!) (module-source-admit-current! inputs))))
            (def (closed!)
              (unless (linked-configuration-guard-active? context-current!)
                (error "configuration source check requires the paired Graph guard"))
              (parameterize ((current-module-source-phase 'configuration-public))
                (module-source-admit-current! evaluated-inputs)
                (context-current!)
                (for-each (lambda (row) ((car row))) source-checks)
                (module-source-admit-current! inputs)))
            (values ordinary! (make-configuration-request-check context-current!
                               ordinary! closed! source-checks-current?))))))))
