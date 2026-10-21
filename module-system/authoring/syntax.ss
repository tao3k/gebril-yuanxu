;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: user-facing Gerbil module authoring and catalog forms.
;;; Invariant: macros expand to hygienic Gerbil bindings and POO values.
;;; Intent: borrow Doom-style compactness without inventing an alist/record DSL.
;;; Parser policy should treat this file as syntax over the public POO API.

(import (only-in :clan/poo/object .o)
        :yuanxu/object-family/role-syntax
        :yuanxu/module-system/catalog/values)

(export defyuanxu-module-object-block
        yuanxu-module-option-block
        yuanxu-module-hook-block
        yuanxu-module-when
        defyuanxu-module-set)

;; : (forall (a) (-> [a] [a] [a]))
(def (yuanxu-module-set-values/tail values tail)
  (append values tail))

;; : (forall (a) (-> [[a]] [a] [a]))
(def (yuanxu-module-set-groups/tail groups tail)
  (if (null? groups)
    tail
    (yuanxu-module-set-values/tail
     (car groups)
     (yuanxu-module-set-groups/tail (cdr groups) tail))))

;; : (forall (a) (-> [a] [[a]] [a]))
(def (yuanxu-module-set-groups->values values groups)
  (yuanxu-module-set-values/tail
   values
   (yuanxu-module-set-groups/tail groups '())))

;;; Boundary: higher-order macro factory for hygienic POO slot blocks.
;;; The generated macro preserves caller bindings and only constructs POO values.
;;; It is not a DSL parser: keyword slots are Gerbil syntax accepted by .o.
;; defyuanxu-module-object-block
;;   : (-> Identifier Syntax)
;;   | doc m%
;;       `defyuanxu-module-object-block` documents the module-system boundary
;;       that the Gerbil policy harness treats as agent-facing behavior. The
;;       example keeps the call shape visible without duplicating
;;       implementation details.
;;
;;       # Examples
;;       ```scheme
;;       (defyuanxu-module-object-block ...)
;;       ;; => policy-visible result
;;       ```
;;     %
(defrules defyuanxu-module-object-block ()
  ((_ macro-name)
   (defrules macro-name ()
     ((_ . slots)
      (.o . slots)))))

;;; Boundary: option blocks are syntax for POO slot objects.
;;; The macro preserves keyword slots and performs no schema validation.
;;; Users may pass the result to interface schemas or module config values.
;; : (-> ModuleOptionKeywordSyntax... POOObject)
(defyuanxu-module-object-block yuanxu-module-option-block)

;;; Boundary: hook blocks become POO objects consumed by descriptor projection.
;;; Hook payload identifiers stay quoted and are never invoked here.
;;; Each hook id owns one list of payload symbols for later runtime owners.
;; yuanxu-module-hook-block
;;   : (-> HookBlockSyntax... ModuleHooks)
;;   | doc m%
;;       `yuanxu-module-hook-block` documents the module-system boundary that
;;       the Gerbil policy harness treats as agent-facing behavior. The example
;;       keeps the call shape visible without duplicating implementation
;;       details.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-hook-block ...)
;;       ;; => policy-visible result
;;       ```
;;     %
(defrules yuanxu-module-hook-block ()
  ((_ (hook-id hook-value ...) ...)
   (poo-core-role-object
    (slots ((hook-id (list 'hook-value ...)) ...))
    (supers (.o)))))

;;; Boundary: conditional module inclusion returns a module list.
;;; The condition is evaluated where the user writes the module set.
;;; No catalog lookup, activation, or source loading occurs in this helper.
;; yuanxu-module-when
;;   : (-> Boolean PooModuleDescriptor... [PooModuleDescriptor])
;;   | doc m%
;;       `yuanxu-module-when` documents the module-system boundary that the
;;       Gerbil policy harness treats as agent-facing behavior. The example
;;       keeps the call shape visible without duplicating implementation
;;       details.
;;
;;       # Examples
;;       ```scheme
;;       (yuanxu-module-when ...)
;;       ;; => policy-visible result
;;       ```
;;     %
(defrules yuanxu-module-when ()
  ((_ condition module ...)
   (if condition
     (list module ...)
     '())))

;;; Boundary: module-set syntax collects already-built POO module values.
;;; Clauses after the required modules block must evaluate to module lists.
;;; The generated catalog is a value catalog and remains activation-free.
;; defyuanxu-module-set
;;   : (-> ModuleSetSyntax PooModuleValueCatalogExpansion)
;;   | doc m%
;;       `defyuanxu-module-set` documents the module-system boundary that the
;;       Gerbil policy harness treats as agent-facing behavior. The example
;;       keeps the call shape visible without duplicating implementation
;;       details.
;;
;;       # Examples
;;       ```scheme
;;       (defyuanxu-module-set ...)
;;       ;; => policy-visible result
;;       ```
;;     %
(defrules defyuanxu-module-set (modules)
  ((_ binding
      (modules module ...)
      module-clause ...)
   (def binding
     (apply yuanxuModuleCatalog
            (yuanxu-module-set-groups->values
             (list module ...)
             (list module-clause ...))))))
