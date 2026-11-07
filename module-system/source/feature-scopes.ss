;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Selected Feature refinements use the same write fence as dependency edges.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/mop Type. define-type element? validate)
        (only-in :yuanxu/module-system/source/publication ModuleFeatureRefinementContract)
        (only-in :yuanxu/module-system/source/admission admit-module-value!))
(export refine-module-scope compose-module-features module-feature-scope-contract)

(def (call-with-scope-protection candidate ancestor action)
  (instantiate-object! candidate)
  (parameterize ((active-object-constructions
                   (cons candidate (cons ancestor (active-object-constructions)))))
    (action)))

(def (refine-module-scope candidate ancestor refine)
  (call-with-scope-protection candidate ancestor (lambda () (refine candidate))))

;; STAGE is the linker's existing supported callback boundary. No result or
;; acceptance verdict is cached here; each selected graph admits independently.
(def (compose-module-features base features stage)
  (let loop ((scope base) (remaining features) (contracts '()))
    (if (null? remaining) (values scope (reverse contracts))
      (let* ((feature (car remaining))
             (id (.ref feature 'feature-id))
             (_checked
               (stage 'feature-declaration id
                 (lambda ()
                   (unless (element? ModuleFeatureRefinementContract feature)
                     (error "invalid Module Feature refinement" id)))))
             (refine (and (.slot? feature 'refine) (.ref feature 'refine)))
             (contract (and (.slot? feature 'contract) (.ref feature 'contract)))
             (next
               (if (not refine) scope
                 (stage 'feature-refinement id
                   (lambda ()
                     (def value (refine-module-scope scope base refine))
                     (unless (object? value)
                       (error "Module Feature refinement must return a POO scope" id))
                     value)))))
        (loop next (cdr remaining)
          (if contract (cons (cons id contract) contracts) contracts))))))

;; Feature Contracts are additional obligations on the SAME Core-normalized
;; receiver. A Feature supplies defaults/transformations through REFINE, not a
;; discarded normalization output. All native validation obligations still run.
(def (check-module-feature-contracts! scope core contracts context stage owner)
  (for-each
    (lambda (entry)
      (stage 'feature-admission (car entry)
        (lambda ()
          (call-with-scope-protection scope scope
            (lambda ()
              (with-catch
                (lambda (cause)
                  (error "Module Feature Contract rejected scope" owner (car entry) cause))
                (lambda () (admit-module-value! (cdr entry) scope context)))
              (unless (element? (cdr entry) scope)
                (error "Module Feature Contract requires refinement of the final scope" (car entry))))))))
    contracts)
  (unless (null? contracts)
    (stage 'feature-core-admission (.ref core 'identity)
      (lambda ()
        (call-with-scope-protection scope scope
          (lambda ()
            (unless (element? core scope)
              (error "Module Feature invalidated its Core Contract" (.ref core 'identity)))))))))

;; Retain the native Type on the linked record: a consumer's later dependency
;; refinement must satisfy the same Feature obligations, not just Core's shape.
(define-type (ModuleFeatureScopeContract. @ Type. provider obligations context stage owner)
  identity: (.ref provider 'identity)
  .element?:
  (lambda (scope)
    (and (element? provider scope)
         (andmap (lambda (entry) (element? (cdr entry) scope)) obligations)))
  .validate:
  (lambda (candidate)
    (def scope (validate provider candidate))
    (check-module-feature-contracts! scope provider obligations context stage owner)
    scope))

(def (module-feature-scope-contract baseline contributions scope-context run-stage owner)
  (if (null? contributions) baseline
    (.cc ModuleFeatureScopeContract.
      provider: baseline obligations: contributions context: scope-context stage: run-stage owner: owner)))
