;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Module System Loader Backend objects and lazy receipts.
;;; Invariant: this owner returns data and never activates product modules.

(import (only-in :clan/poo/object .ref .get .cc)
        (only-in :clan/poo/mop make-instance validate)
        (only-in :std/list/list find)
        (only-in :yuanxu/module-system/source/types ModuleSourceBinding)
        "types.ss"
        :yuanxu/module-system/source/objects)

(export ModuleSourceBinding ModuleLoaderBackend
        LazyLoadPlan ModuleLoadReceipt
        yuanxu-module-static-loader
        yuanxu-module-loader-backend-supports?
        yuanxu-lazy-load-source-receipt
        yuanxu-make-lazy-load-plan
        yuanxu-force-lazy-load-plan
        yuanxu-module-load-source-receipt
        yuanxu-module-load-source-receipts
        yuanxu-module-load-receipt->alist)


;;; Boundary: wildcard source kind is explicit and does not inspect source values.
;; : (-> SourceKind PooModuleSourceRef Boolean)
(def (yuanxu-module-loader-source-kind-matches? source-kind source-ref)
  (or (eq? source-kind '*)
      (eq? source-kind (yuanxu-module-source-ref-kind source-ref))))

;;; Boundary: static loaders use source-ref equality, never path reads.
;; : (-> [ModuleSourceBinding] PooModuleSourceRef (OrFalse ModuleSourceBinding))
(def (yuanxu-module-static-loader-find-entry entries source-ref)
  (find (lambda (entry)
          (yuanxu-module-source-ref=? (.get entry source) source-ref))
        entries))

;;; Boundary: static loader handler returns a descriptor or false.
;; : (-> [ModuleSourceBinding] PooModuleSourceRef MaybePooModuleDescriptor)
(def (yuanxu-module-static-loader-load entries source-ref)
  (let (entry (yuanxu-module-static-loader-find-entry entries source-ref))
    (if entry
      (.get entry module)
      #f)))

;;; Boundary: static loaders are useful for manifests and tests before IO backends exist.
;; : (-> LoaderName SourceKind [ModuleSourceBinding] ModuleLoaderBackend)
(def (yuanxu-module-static-loader loader-name source-kind entries)
  (make-instance ModuleLoaderBackend name: loader-name source-kind: source-kind
   load: (lambda (source-ref)
     (yuanxu-module-static-loader-load entries source-ref))
   metadata: (list (cons 'mode 'static)
         (cons 'entry-count (length entries)))))

;;; Boundary: support checks only source kind, not filesystem or registry state.
;; : (-> ModuleLoaderBackend PooModuleSourceRef Boolean)
(def (yuanxu-module-loader-backend-supports? backend source-ref)
  (yuanxu-module-loader-source-kind-matches?
   (.get backend source-kind)
   source-ref))

;;; Boundary: successful receipt records the backend that produced the descriptor.
;; : (-> ModuleLoaderBackend PooModuleSourceRef PooModuleDescriptor ModuleLoadReceipt)
(def (yuanxu-module-loaded-receipt backend source-ref module)
  (make-instance ModuleLoadReceipt
   source: source-ref module: module
   backend-name: (.get backend name)
   loaded?: #t code: 'loaded
   metadata: (.get backend metadata)))

;;; Boundary: missing loader receipts remain data until callers request strict loading.
;; : (-> PooModuleSourceRef ModuleLoadReceipt)
(def (yuanxu-module-missing-loader-receipt source-ref)
  (make-instance ModuleLoadReceipt source: source-ref code: 'missing-loader
    messages: '("poo module source was not loaded by any backend")))

;;; Boundary: lazy metadata marks the deferred state as disabled-by-default.
;; : (-> [ModuleLoaderBackend] Alist Alist)
(def (yuanxu-lazy-loader-metadata backends metadata)
  (append
   (list (cons 'mode 'lazy)
         (cons 'enabled? #f)
         (cons 'forced? #f)
         (cons 'backend-count (length backends)))
   metadata))

;;; Boundary: lazy receipts are explicit non-load evidence, not failures.
;; : (-> [ModuleLoaderBackend] PooModuleSourceRef Alist ModuleLoadReceipt)
(def (yuanxu-lazy-load-source-receipt backends source-ref . maybe-metadata)
  (let (metadata
        (if (null? maybe-metadata) '() (car maybe-metadata)))
    (make-instance ModuleLoadReceipt source: source-ref code: 'deferred
      messages: '("poo module source loading is deferred until forced")
      metadata: (yuanxu-lazy-loader-metadata backends metadata))))

;;; Boundary: lazy plans preserve loader order but do not call loader handlers.
;; : (-> [ModuleLoaderBackend] PooModuleSourceRef Alist LazyLoadPlan)
(def (yuanxu-make-lazy-load-plan backends source-ref . maybe-metadata)
  (let* ((metadata
          (if (null? maybe-metadata) '() (car maybe-metadata)))
         (receipt
          (yuanxu-lazy-load-source-receipt backends
                                             source-ref
                                             metadata)))
    (make-instance LazyLoadPlan source: source-ref backends: backends
      receipt: receipt metadata: metadata)))

;;; Boundary: forcing returns a new plan value and leaves the deferred plan intact.
;; : (-> LazyLoadPlan LazyLoadPlan)
(def (yuanxu-force-lazy-load-plan lazy-plan)
  (let (receipt
        (yuanxu-module-load-source-receipt
         (.get lazy-plan backends)
         (.get lazy-plan source)))
    (validate LazyLoadPlan (.cc lazy-plan forced?: #t receipt: receipt))))

;;; Boundary: backend attempts are ordered and stop at the first descriptor.
;; : (-> [ModuleLoaderBackend] PooModuleSourceRef ModuleLoadReceipt)
(def (yuanxu-module-load-source-receipt backends source-ref)
  (cond
   ((null? backends)
    (yuanxu-module-missing-loader-receipt source-ref))
   ((not (yuanxu-module-loader-backend-supports? (car backends) source-ref))
    (yuanxu-module-load-source-receipt (cdr backends) source-ref))
   (else
    (let (module ((.get (car backends) load) source-ref))
      (if module
        (yuanxu-module-loaded-receipt (car backends) source-ref module)
        (yuanxu-module-load-source-receipt (cdr backends) source-ref))))))

;;; Boundary: module load source receipts is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> [ModuleLoaderBackend] [PooModuleSourceRef] [ModuleLoadReceipt])
(def (yuanxu-module-load-source-receipts backends source-refs)
  (if (null? source-refs)
    '()
    (cons (yuanxu-module-load-source-receipt backends (car source-refs))
          (yuanxu-module-load-source-receipts backends (cdr source-refs)))))

;;; Boundary: receipt projection is stable evidence for doctors and user tooling.
;;; A backend result is an opaque POO Module; only its name slot is observed.
;; : (-> ModuleLoadReceipt Alist)
(def (yuanxu-module-load-receipt->alist receipt)
  (let (module (.get receipt module))
    (list
     (cons 'source
           (yuanxu-module-source-ref->alist
            (.get receipt source)))
     (cons 'module (if module (.ref module 'name) #f))
     (cons 'backend-name (.get receipt backend-name))
     (cons 'loaded? (.get receipt loaded?))
     (cons 'code (.get receipt code))
     (cons 'messages (.get receipt messages))
     (cons 'metadata (.get receipt metadata)))))
