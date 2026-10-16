;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure source graph and existing lazy-plan projection; never forces a backend.
(import :core/module-system/source/objects
        :core/module-system/loader/objects
        :core/extension-graph/interface)
(export poo-flow-module-source-refs->lazy-load-plans
        poo-flow-module-auto-import-root-identity
        poo-flow-module-auto-import-entry-node
        poo-flow-module-auto-imports-node
        poo-flow-module-auto-imports-resolve
        poo-flow-module-auto-imports-result-source-refs)

;; : (-> [PooModuleLoaderBackend] [PooModuleSourceRef] Alist [PooFlowLazyLoadPlan] [PooFlowLazyLoadPlan])
(def (poo-flow-module-source-refs->lazy-load-plans/rev
      backends
      source-refs
      metadata
      plans-rev)
  (if (null? source-refs)
    plans-rev
    (poo-flow-module-source-refs->lazy-load-plans/rev
     backends
     (cdr source-refs)
     metadata
     (cons (poo-flow-make-lazy-load-plan backends
                                          (car source-refs)
                                          metadata)
           plans-rev))))

;; : (-> [PooModuleLoaderBackend] [PooModuleSourceRef] Alist [PooFlowLazyLoadPlan])
(def (poo-flow-module-source-refs->lazy-load-plans backends source-refs metadata)
  (reverse
   (poo-flow-module-source-refs->lazy-load-plans/rev
    backends
    source-refs
    metadata
    '())))

;;; Boundary: tree loading remains lazy data until callers force a plan.
;;; Boundary: auto-import plans are POO nodes over source refs, not evaluator IO.
;; : PooFlowModuleAutoImportRootIdentity
(def poo-flow-module-auto-import-root-identity 'auto-imports)

;;; Boundary: loader alist ref default is the policy-visible edge for module-
;;; system behavior, keeping validation, lookup, or projection responsibilities
;;; centralized for callers.
;; : (-> PooModuleLoaderMetadata Symbol PooModuleLoaderMetadataValue PooModuleLoaderMetadataValue)
(def (poo-flow-loader-alist-ref/default entries key default-value)
  (let (entry (assoc key entries))
    (if entry (cdr entry) default-value)))

;;; Boundary: each source ref is an importable entrypoint node.
;; : (-> PooModuleSourceRef PooModuleExtensionNode)
(def (poo-flow-module-auto-import-entry-node source-ref)
  (let* ((metadata (poo-flow-module-source-ref-metadata source-ref))
         (entrypoint-role
          (poo-flow-loader-alist-ref/default metadata 'entrypoint-role #f))
         (tree-kind
          (poo-flow-loader-alist-ref/default metadata 'kind #f)))
    (poo-flow-module-extension-node
     (poo-flow-module-source-ref-value source-ref)
     (list (cons 'source-ref source-ref)
           (cons 'entrypoint-role entrypoint-role)
           (cons 'tree-kind tree-kind)
           (cons 'allowed-responsibilities
                 (poo-flow-loader-alist-ref/default
                  metadata
                  'allowed-responsibilities
                  '()))
           (cons 'denied-responsibilities
                 (poo-flow-loader-alist-ref/default
                  metadata
                  'denied-responsibilities
                  '()))
           (cons 'enabled? #t))
     '())))

;;; Boundary: auto-import roots are POO graphs so extensions can remove entries.
;; : (-> [PooModuleSourceRef] PooModuleExtensionNode)
(def (poo-flow-module-auto-imports-node source-refs)
  (poo-flow-module-extension-node
   poo-flow-module-auto-import-root-identity
   '((namespace . auto-imports))
   (map poo-flow-module-auto-import-entry-node source-refs)))

;;; Boundary: disabling an auto import is a regular node-remove contribution.
;; : (-> [PooModuleSourceRef] [PooModuleExtensionContribution] PooModuleExtensionResult)
(def (poo-flow-module-auto-imports-resolve source-refs contributions)
  (poo-flow-module-extension-resolve
   (poo-flow-module-auto-imports-node source-refs)
   contributions))

;; : (-> PooModuleExtensionNode MaybePooModuleSourceRef)
(def (poo-flow-module-auto-import-entry-source-ref entry-node)
  (poo-flow-loader-alist-ref/default
   (poo-flow-module-extension-node-slots entry-node)
   'source-ref
   #f))

;;; Boundary: resolved source refs are read after POO removals/extensions apply.
;; : (-> PooModuleExtensionResult [PooModuleSourceRef])
(def (poo-flow-module-auto-imports-result-source-refs result)
  (let (root (poo-flow-module-extension-result-root result))
    (map poo-flow-module-auto-import-entry-source-ref
         (poo-flow-module-extension-node-children root))))

