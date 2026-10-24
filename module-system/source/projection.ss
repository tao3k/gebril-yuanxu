;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure source graph and existing lazy-plan projection; never forces a backend.
(import :yuanxu/module-system/source/objects
        :yuanxu/module-system/loader/objects
        :yuanxu/graph/interface)
(export yuanxu-module-source-refs->lazy-load-plans
        yuanxu-module-auto-import-root-identity
        yuanxu-module-auto-import-entry-node
        yuanxu-module-auto-imports-node
        yuanxu-module-auto-imports-resolve
        yuanxu-module-auto-imports-result-source-refs)

;; : (-> [PooModuleLoaderBackend] [PooModuleSourceRef] Alist [YuanxuLazyLoadPlan] [YuanxuLazyLoadPlan])
(def (yuanxu-module-source-refs->lazy-load-plans/rev
      backends
      source-refs
      metadata
      plans-rev)
  (if (null? source-refs)
    plans-rev
    (yuanxu-module-source-refs->lazy-load-plans/rev
     backends
     (cdr source-refs)
     metadata
     (cons (yuanxu-make-lazy-load-plan backends
                                          (car source-refs)
                                          metadata)
           plans-rev))))

;; : (-> [PooModuleLoaderBackend] [PooModuleSourceRef] Alist [YuanxuLazyLoadPlan])
(def (yuanxu-module-source-refs->lazy-load-plans backends source-refs metadata)
  (reverse
   (yuanxu-module-source-refs->lazy-load-plans/rev
    backends
    source-refs
    metadata
    '())))

;;; Boundary: tree loading remains lazy data until callers force a plan.
;;; Boundary: auto-import plans are POO nodes over source refs, not evaluator IO.
;; : YuanxuModuleAutoImportRootIdentity
(def yuanxu-module-auto-import-root-identity 'auto-imports)

;;; Boundary: loader alist ref default is the policy-visible edge for module-
;;; system behavior, keeping validation, lookup, or projection responsibilities
;;; centralized for callers.
;; : (-> PooModuleLoaderMetadata Symbol PooModuleLoaderMetadataValue PooModuleLoaderMetadataValue)
(def (yuanxu-loader-alist-ref/default entries key default-value)
  (let (entry (assoc key entries))
    (if entry (cdr entry) default-value)))

;;; Boundary: each source ref is an importable entrypoint node.
;; : (-> PooModuleSourceRef YuanxuGraph)
(def (yuanxu-module-auto-import-entry-node source-ref)
  (let* ((metadata (yuanxu-module-source-ref-metadata source-ref))
         (entrypoint-role
          (yuanxu-loader-alist-ref/default metadata 'entrypoint-role #f))
         (tree-kind
          (yuanxu-loader-alist-ref/default metadata 'kind #f)))
    (yuanxu-graph-rooted
     (yuanxu-module-source-ref-value source-ref)
     (list (cons 'source-ref source-ref)
           (cons 'entrypoint-role entrypoint-role)
           (cons 'tree-kind tree-kind)
           (cons 'allowed-responsibilities
                 (yuanxu-loader-alist-ref/default
                  metadata
                  'allowed-responsibilities
                  '()))
           (cons 'denied-responsibilities
                 (yuanxu-loader-alist-ref/default
                  metadata
                  'denied-responsibilities
                  '()))
           (cons 'enabled? #t))
     '())))

;;; Boundary: auto-import roots are POO graphs so extensions can remove entries.
;; : (-> [PooModuleSourceRef] YuanxuGraph)
(def (yuanxu-module-auto-imports-node source-refs)
  (yuanxu-graph-rooted
   yuanxu-module-auto-import-root-identity
   '((namespace . auto-imports))
   (map yuanxu-module-auto-import-entry-node source-refs)))

;;; Boundary: disabling an auto import is a regular node-remove contribution.
;; : (-> [PooModuleSourceRef] [PooGraphContribution] PooGraphResult)
(def (yuanxu-module-auto-imports-resolve source-refs contributions)
  (yuanxu-graph-resolve
   (yuanxu-module-auto-imports-node source-refs)
   contributions))

;; : (-> YuanxuGraph MaybePooModuleSourceRef)
(def (yuanxu-module-auto-import-entry-source-ref entry-node)
  (yuanxu-loader-alist-ref/default
   (yuanxu-graph-root-payload entry-node)
   'source-ref
   #f))

;;; Boundary: resolved source refs are read after POO removals/extensions apply.
;; : (-> PooGraphResult [PooModuleSourceRef])
(def (yuanxu-module-auto-imports-result-source-refs result)
  (let (root (yuanxu-graph-result-root result))
    (map yuanxu-module-auto-import-entry-source-ref
         (yuanxu-graph-root-children root))))

