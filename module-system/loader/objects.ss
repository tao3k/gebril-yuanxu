;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Module System Loader Backend objects and lazy receipts.
;;; Invariant: this owner returns data and never activates product modules.

(import (only-in :clan/poo/object .ref)
        (only-in :yuanxu/object-family/syntax
                 defpoo-object-family)
        :yuanxu/module-system/source/objects)

(export yuanxu-module-loader-entry-prototype
        make-yuanxu-module-loader-entry
        yuanxu-module-loader-entry?
        yuanxu-module-loader-entry-source
        yuanxu-module-loader-entry-module
        yuanxu-module-loader-backend-prototype
        make-yuanxu-module-loader-backend
        yuanxu-module-loader-backend?
        yuanxu-module-loader-backend-name
        yuanxu-module-loader-backend-source-kind
        yuanxu-module-loader-backend-load
        yuanxu-module-loader-backend-metadata
        yuanxu-lazy-load-plan-prototype
        make-yuanxu-lazy-load-plan
        yuanxu-lazy-load-plan?
        yuanxu-lazy-load-plan-source
        yuanxu-lazy-load-plan-backends
        yuanxu-lazy-load-plan-forced?
        yuanxu-lazy-load-plan-receipt
        yuanxu-lazy-load-plan-metadata
        yuanxu-module-load-receipt-prototype
        make-yuanxu-module-load-receipt
        yuanxu-module-load-receipt?
        yuanxu-module-load-receipt-source
        yuanxu-module-load-receipt-module
        yuanxu-module-load-receipt-backend-name
        yuanxu-module-load-receipt-loaded?
        yuanxu-module-load-receipt-code
        yuanxu-module-load-receipt-messages
        yuanxu-module-load-receipt-metadata
        yuanxu-module-static-loader
        yuanxu-module-loader-backend-supports?
        yuanxu-lazy-load-source-receipt
        yuanxu-make-lazy-load-plan
        yuanxu-force-lazy-load-source-receipt
        yuanxu-force-lazy-load-plan
        yuanxu-module-load-source-receipt
        yuanxu-module-load-source-receipts
        yuanxu-module-load-receipt->alist)


;;; Boundary: static loader entries bind source refs to already-built descriptors.
;; : (-> PooModuleSourceRef PooModuleDescriptor PooModuleLoaderEntry)
(defpoo-object-family
  (prototype yuanxu-module-loader-entry-prototype
             loader-entry?
             yuanxu-module-loader-entry?)
  (constructor make-yuanxu-module-loader-entry
               (source-value source)
               (module-value module))
  (accessors
   (yuanxu-module-loader-entry-source source)
   (yuanxu-module-loader-entry-module module))
  (projections))

;;; Boundary: backend load procedures are pure source-ref to maybe descriptor functions.
;; : (-> LoaderName SourceKind LoaderProcedure Alist PooModuleLoaderBackend)
(defpoo-object-family
  (prototype yuanxu-module-loader-backend-prototype
             loader-backend?
             yuanxu-module-loader-backend?)
  (constructor make-yuanxu-module-loader-backend
               (name-value name)
               (source-kind-value source-kind)
               (load-value load)
               (metadata-value metadata))
  (accessors
   (yuanxu-module-loader-backend-name name)
   (yuanxu-module-loader-backend-source-kind source-kind)
   (yuanxu-module-loader-backend-load load)
   (yuanxu-module-loader-backend-metadata metadata))
  (projections))

;;; Boundary: lazy load plans hold source/backend data without invoking loaders.
;; : (-> PooModuleSourceRef [PooModuleLoaderBackend] Boolean PooModuleLoadReceipt Alist YuanxuLazyLoadPlan)
(defpoo-object-family
  (prototype yuanxu-lazy-load-plan-prototype
             lazy-load-plan?
             yuanxu-lazy-load-plan?)
  (constructor make-yuanxu-lazy-load-plan
               (source-value source)
               (backends-value backends)
               (forced-value forced?)
               (receipt-value receipt)
               (metadata-value metadata))
  (accessors
   (yuanxu-lazy-load-plan-source source)
   (yuanxu-lazy-load-plan-backends backends)
   (yuanxu-lazy-load-plan-forced? forced?)
   (yuanxu-lazy-load-plan-receipt receipt)
   (yuanxu-lazy-load-plan-metadata metadata))
  (projections))

;;; Boundary: load receipts are inspection data before catalog resolution.
;; : (-> PooModuleSourceRef MaybePooModuleDescriptor MaybeLoaderName Boolean Symbol [String] Alist PooModuleLoadReceipt)
(defpoo-object-family
  (prototype yuanxu-module-load-receipt-prototype
             load-receipt?
             yuanxu-module-load-receipt?)
  (constructor make-yuanxu-module-load-receipt
               (source-value source)
               (module-value module)
               (backend-name-value backend-name)
               (loaded-value loaded?)
               (code-value code)
               (messages-value messages)
               (metadata-value metadata))
  (accessors
   (yuanxu-module-load-receipt-source source)
   (yuanxu-module-load-receipt-module module)
   (yuanxu-module-load-receipt-backend-name backend-name)
   (yuanxu-module-load-receipt-loaded? loaded?)
   (yuanxu-module-load-receipt-code code)
   (yuanxu-module-load-receipt-messages messages)
   (yuanxu-module-load-receipt-metadata metadata))
  (projections))

;;; Boundary: wildcard source kind is explicit and does not inspect source values.
;; : (-> SourceKind PooModuleSourceRef Boolean)
(def (yuanxu-module-loader-source-kind-matches? source-kind source-ref)
  (or (eq? source-kind '*)
      (eq? source-kind (yuanxu-module-source-ref-kind source-ref))))

;;; Boundary: static loaders use source-ref equality, never path reads.
;; : (-> [PooModuleLoaderEntry] PooModuleSourceRef MaybePooModuleLoaderEntry)
(def (yuanxu-module-static-loader-find-entry entries source-ref)
  (cond
   ((null? entries) #f)
   ((yuanxu-module-source-ref=? (yuanxu-module-loader-entry-source (car entries))
                                  source-ref)
    (car entries))
   (else
    (yuanxu-module-static-loader-find-entry (cdr entries) source-ref))))

;;; Boundary: static loader handler returns a descriptor or false.
;; : (-> [PooModuleLoaderEntry] PooModuleSourceRef MaybePooModuleDescriptor)
(def (yuanxu-module-static-loader-load entries source-ref)
  (let (entry (yuanxu-module-static-loader-find-entry entries source-ref))
    (if entry
      (yuanxu-module-loader-entry-module entry)
      #f)))

;;; Boundary: static loaders are useful for manifests and tests before IO backends exist.
;; : (-> LoaderName SourceKind [PooModuleLoaderEntry] PooModuleLoaderBackend)
(def (yuanxu-module-static-loader loader-name source-kind entries)
  (make-yuanxu-module-loader-backend
   loader-name
   source-kind
   (lambda (source-ref)
     (yuanxu-module-static-loader-load entries source-ref))
   (list (cons 'mode 'static)
         (cons 'entry-count (length entries)))))

;;; Boundary: support checks only source kind, not filesystem or registry state.
;; : (-> PooModuleLoaderBackend PooModuleSourceRef Boolean)
(def (yuanxu-module-loader-backend-supports? backend source-ref)
  (yuanxu-module-loader-source-kind-matches?
   (yuanxu-module-loader-backend-source-kind backend)
   source-ref))

;;; Boundary: successful receipt records the backend that produced the descriptor.
;; : (-> PooModuleLoaderBackend PooModuleSourceRef PooModuleDescriptor PooModuleLoadReceipt)
(def (yuanxu-module-loaded-receipt backend source-ref module)
  (make-yuanxu-module-load-receipt
   source-ref
   module
   (yuanxu-module-loader-backend-name backend)
   #t
   'loaded
   '()
   (yuanxu-module-loader-backend-metadata backend)))

;;; Boundary: missing loader receipts remain data until callers request strict loading.
;; : (-> PooModuleSourceRef PooModuleLoadReceipt)
(def (yuanxu-module-missing-loader-receipt source-ref)
  (make-yuanxu-module-load-receipt
   source-ref
   #f
   #f
   #f
   'missing-loader
   '("poo module source was not loaded by any backend")
   '()))

;;; Boundary: lazy metadata marks the deferred state as disabled-by-default.
;; : (-> [PooModuleLoaderBackend] Alist Alist)
(def (yuanxu-lazy-loader-metadata backends metadata)
  (append
   (list (cons 'mode 'lazy)
         (cons 'enabled? #f)
         (cons 'forced? #f)
         (cons 'backend-count (length backends)))
   metadata))

;;; Boundary: lazy receipts are explicit non-load evidence, not failures.
;; : (-> [PooModuleLoaderBackend] PooModuleSourceRef Alist PooModuleLoadReceipt)
(def (yuanxu-lazy-load-source-receipt backends source-ref . maybe-metadata)
  (let (metadata
        (if (null? maybe-metadata) '() (car maybe-metadata)))
    (make-yuanxu-module-load-receipt
     source-ref
     #f
     #f
     #f
     'deferred
     '("poo module source loading is deferred until forced")
     (yuanxu-lazy-loader-metadata backends metadata))))

;;; Boundary: lazy plans preserve loader order but do not call loader handlers.
;; : (-> [PooModuleLoaderBackend] PooModuleSourceRef Alist YuanxuLazyLoadPlan)
(def (yuanxu-make-lazy-load-plan backends source-ref . maybe-metadata)
  (let* ((metadata
          (if (null? maybe-metadata) '() (car maybe-metadata)))
         (receipt
          (yuanxu-lazy-load-source-receipt backends
                                             source-ref
                                             metadata)))
    (make-yuanxu-lazy-load-plan
     source-ref
     backends
     #f
     receipt
     metadata)))

;;; Boundary: forcing a lazy source delegates to the existing strict receipt path.
;; : (-> [PooModuleLoaderBackend] PooModuleSourceRef PooModuleLoadReceipt)
(def (yuanxu-force-lazy-load-source-receipt backends source-ref)
  (yuanxu-module-load-source-receipt backends source-ref))

;;; Boundary: forcing returns a new plan value and leaves the deferred plan intact.
;; : (-> YuanxuLazyLoadPlan YuanxuLazyLoadPlan)
(def (yuanxu-force-lazy-load-plan lazy-plan)
  (let (receipt
        (yuanxu-force-lazy-load-source-receipt
         (yuanxu-lazy-load-plan-backends lazy-plan)
         (yuanxu-lazy-load-plan-source lazy-plan)))
    (make-yuanxu-lazy-load-plan
     (yuanxu-lazy-load-plan-source lazy-plan)
     (yuanxu-lazy-load-plan-backends lazy-plan)
     #t
     receipt
     (yuanxu-lazy-load-plan-metadata lazy-plan))))

;;; Boundary: backend attempts are ordered and stop at the first descriptor.
;; : (-> [PooModuleLoaderBackend] PooModuleSourceRef PooModuleLoadReceipt)
(def (yuanxu-module-load-source-receipt backends source-ref)
  (cond
   ((null? backends)
    (yuanxu-module-missing-loader-receipt source-ref))
   ((not (yuanxu-module-loader-backend-supports? (car backends) source-ref))
    (yuanxu-module-load-source-receipt (cdr backends) source-ref))
   (else
    (let (module ((yuanxu-module-loader-backend-load (car backends)) source-ref))
      (if module
        (yuanxu-module-loaded-receipt (car backends) source-ref module)
        (yuanxu-module-load-source-receipt (cdr backends) source-ref))))))

;;; Boundary: module load source receipts is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> [PooModuleLoaderBackend] [PooModuleSourceRef] [PooModuleLoadReceipt])
(def (yuanxu-module-load-source-receipts backends source-refs)
  (if (null? source-refs)
    '()
    (cons (yuanxu-module-load-source-receipt backends (car source-refs))
          (yuanxu-module-load-source-receipts backends (cdr source-refs)))))

;;; Boundary: receipt projection is stable evidence for doctors and user tooling.
;;; A backend result is an opaque POO Module; only its name slot is observed.
;; : (-> PooModuleLoadReceipt Alist)
(def (yuanxu-module-load-receipt->alist receipt)
  (let (module (yuanxu-module-load-receipt-module receipt))
    (list
     (cons 'source
           (yuanxu-module-source-ref->alist
            (yuanxu-module-load-receipt-source receipt)))
     (cons 'module (if module (.ref module 'name) #f))
     (cons 'backend-name (yuanxu-module-load-receipt-backend-name receipt))
     (cons 'loaded? (yuanxu-module-load-receipt-loaded? receipt))
     (cons 'code (yuanxu-module-load-receipt-code receipt))
     (cons 'messages (yuanxu-module-load-receipt-messages receipt))
     (cons 'metadata (yuanxu-module-load-receipt-metadata receipt)))))
