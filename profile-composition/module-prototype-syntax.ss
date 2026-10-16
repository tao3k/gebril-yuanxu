;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Bootstrap declarations only; importing prototypes must not import selection.
(import (only-in :clan/poo/object .ref .slot? object? object<-alist))
(export defpoo-module-config-prototype defpoo-module-config-kind-predicate)

;;; Prototype macros define named POO config objects from bounded slot rows.
;; defpoo-module-config-prototype
;; : (-> Syntax Syntax Syntax)
;; | type ConfigBindingSyntax = Syntax
;; | type ConfigSlotRowsSyntax = Syntax
;; | type ConfigPrototypeSyntax = Syntax
;; | contract: expands bounded literal slots through clan/poo's native object constructor
;; | warning: keep object inheritance and merge policy outside this syntax helper
;; | doc m%
;;   Defines a module config prototype object.
;;   # Examples
;;   ```scheme
;;   (defpoo-module-config-prototype workflow-prototype (slots ((kind 'workflow))))
;;   ;; => workflow-prototype is bound to a POO object with kind
;;   ```
(defrules defpoo-module-config-prototype
  (slots)
  ((_ binding
      (slots ((slot-key slot-value) ...)))
   (def binding
     (object<-alist
      (list (cons 'slot-key slot-value) ...)))))

;;; Predicate macros generate kind guards over POO config prototypes.
;; defpoo-module-config-kind-predicate
;; : (-> Syntax Syntax)
;; | type PredicateBindingSyntax = Syntax
;; | type ConfigKindSyntax = Syntax
;; | type KindPredicateSyntax = Syntax
;; | contract: expands a predicate binding and expected kind into an object guard
;; | warning: this helper checks only the `kind` slot, not full object validation
;; | doc m%
;;   Defines a predicate for module config object kinds.
;;   # Examples
;;   ```scheme
;;   (defpoo-module-config-kind-predicate workflow-config? 'workflow)
;;   ;; => workflow-config? accepts objects whose kind is workflow
;;   ```
(defrule (defpoo-module-config-kind-predicate predicate kind-expr)
  (def (predicate value)
    (and (object? value)
         (.slot? value 'kind)
         (eq? (.ref value 'kind) kind-expr))))
