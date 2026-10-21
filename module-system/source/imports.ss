;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: Yuanxu import conventions over Core SourceRef identities.
;;; Invariant: imports describe source refs or inline profiles.
;;; They never load files, query registries, or evaluate modules.
;;; Intent: callers can inspect provenance and profile payloads before any loader exists.
;;; Ownership: Core owns inert import/source composition and qualified provenance.
;;; Descriptors may inspect the profile slot to expand inline modules.
;;; Catalogs may compare source refs by kind/value for deterministic lookup.
;;; Future loader backends must consume these values from outside this owner.
;;; Source readers and runtime backends remain separate capabilities.
;;; No function here may read a path, query a registry, or evaluate a profile.
;; | SourceRefValue = Path | Symbol | PooModuleSourceRef | Value
;; | PooModuleSourceRefCandidate = Value

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :yuanxu/module-system/config yuanxu-module-kind=?)
        :yuanxu/module-system/source/objects)

(export make-yuanxu-module-custom-interface-source
        make-yuanxu-module-custom-collection-source
        yuanxu-module-custom-interface-entrypoint
        yuanxu-local-source
        yuanxu-custom-source
        yuanxu-standard-library-source
        yuanxu-source-ref
        yuanxu-module-import-source-ref?
        yuanxu-module-import-local-source?
        yuanxu-module-import-normalize-source
        yuanxu-import
        yuanxu-imports
        yuanxu-imports-append
        yuanxu-extensions
        yuanxu-extensions-append
        yuanxu-import?)

(def yuanxu-module-import-kind "yuanxu.modules.import.v1")
(def yuanxu-module-import-source-ref-kind "yuanxu.modules.import.source-ref.v1")
(def yuanxu-module-import-local-source-kind "yuanxu.modules.import.local-source.v1")

;;; Boundary: custom module directories are user-owned; the module-system only
;;; records the interface.ss entrypoint that a future loader may consume.
;; : (-> Path Path)
(def (yuanxu-module-custom-interface-entrypoint module-root-path)
  (let ((path-length (string-length module-root-path)))
    (if (and (> path-length 0)
             (char=? (string-ref module-root-path (- path-length 1)) #\/))
      (string-append module-root-path "interface.ss")
      (string-append module-root-path "/interface.ss"))))

;;; Boundary: custom sources stay local source refs so loader matching remains
;;; deterministic; root/entrypoint details live in metadata.
;; : (-> Path PooModuleSourceRef)
(def (make-yuanxu-module-custom-interface-source module-root-path)
  (let ((entrypoint
         (yuanxu-module-custom-interface-entrypoint module-root-path)))
    (make-yuanxu-module-source-ref 'local entrypoint
                                     (list
                                      (cons 'kind
                                            yuanxu-module-import-local-source-kind)
                                      (cons 'custom-module-root module-root-path)
                                      (cons 'entrypoint entrypoint)
                                      (cons 'entrypoint-role 'interface)))))

;;; Boundary: an explicit @ modules path selects a directory collection. The
;;; loader expands its direct child module trees; the declaration macro does no
;;; filesystem discovery itself.
;; : (-> Path PooModuleSourceRef)
(def (make-yuanxu-module-custom-collection-source modules-root-path)
  (make-yuanxu-module-source-ref
   'local
   modules-root-path
   (list (cons 'kind 'custom-module-collection)
         (cons 'modules-root modules-root-path)
         (cons 'entrypoint-role 'discover))))

;;; Boundary: import-local sources are catalog-compatible source refs.
;; : (-> Path PooModuleSourceRef)
(def (yuanxu-local-source source-path)
  (make-yuanxu-module-source-ref 'local source-path
                                   (list (cons 'kind yuanxu-module-import-local-source-kind))))

;;; Boundary: user-facing shorthand for a custom module directory.
;; : (-> Path PooModuleSourceRef)
(def (yuanxu-custom-source module-root-path)
  (make-yuanxu-module-custom-interface-source module-root-path))

;;; Boundary: shorthand for upstream standard-library module source refs.
;; : (-> Symbol PooModuleSourceRef)
(def (yuanxu-standard-library-source module-name)
  (make-yuanxu-module-standard-library-source module-name))

;;; Boundary: arbitrary source values are wrapped without interpretation.
;; : (-> SourceRefInput PooModuleSourceRef)
(def (yuanxu-source-ref source-value)
  (cond
   ((yuanxu-module-source-ref? source-value) source-value)
   (else
    (make-yuanxu-module-source-ref
     'source
     source-value
     (list (cons 'kind yuanxu-module-import-source-ref-kind))))))

;; : (-> SourceRefInput Boolean)
(def (yuanxu-module-import-source-ref? value)
  (yuanxu-module-source-ref? value))

;; : (-> SourceRefInput Boolean)
(def (yuanxu-module-import-local-source? value)
  (and (yuanxu-module-source-ref? value)
       (eq? (yuanxu-module-source-ref-kind value) 'local)))

;;; Boundary: module import normalize source is the policy-visible edge for
;;; module-system behavior, keeping validation, lookup, or projection
;;; responsibilities centralized for callers.
;; : (-> SourceRefInput PooModuleSourceRef)
(def (yuanxu-module-import-normalize-source source-value)
  (cond
   ((string? source-value)
    (yuanxu-local-source source-value))
   ((yuanxu-module-import-source-ref? source-value)
    source-value)
   (else
    (yuanxu-source-ref source-value))))

;;; Boundary: import values keep source identity separate from profile payloads.
;;; Intent: a source/profile pair can be resolved or projected without parsing a file path.
;; : (-> MaybePooModuleSourceRef ModuleImportProfile PooImport)
(def (make-yuanxu-import source-ref-value profile-value)
  (.o kind: yuanxu-module-import-kind
      source-ref: source-ref-value
      profile: profile-value))

;;; Boundary: one-arg import is profile-only, two-arg import binds source+profile.
;; : (-> ModuleImportArg... PooImport)
(def (yuanxu-import . import-values)
  (cond
   ;; Profile-only imports are already in-memory module/profile values.
   ((= (length import-values) 1)
    (make-yuanxu-import #f (car import-values)))
   ;; Source/profile imports preserve source identity without invoking a loader.
   ((= (length import-values) 2)
    (make-yuanxu-import
     (yuanxu-module-import-normalize-source (car import-values))
     (cadr import-values)))
   (else
    (error "yuanxu-import expects profile or source/profile"))))

;;; Boundary: import lists preserve caller order for closure expansion.
;; : (-> ModuleImportValue... [ModuleImportValue])
(def (yuanxu-imports . import-values)
  import-values)

;;; Boundary: inherited imports are prepended before direct imports.
;; : (-> [PooImport] [PooImport] [PooImport])
(def (yuanxu-imports-append inherited-imports direct-imports)
  (append inherited-imports direct-imports))

;;; Boundary: extensions stay first-class values until projection.
;; : (-> ModuleExtension... [ModuleExtension])
(def (yuanxu-extensions . extension-values)
  extension-values)

;;; Boundary: inherited extensions are prepended before direct extensions.
;; : (-> [ModuleExtension] [ModuleExtension] [ModuleExtension])
(def (yuanxu-extensions-append inherited-extensions direct-extensions)
  (append inherited-extensions direct-extensions))

;; : (-> ModuleImportCandidate Boolean)
(def (yuanxu-import? value)
  (and (object? value)
       (.slot? value 'kind)
       (yuanxu-module-kind=? (.ref value 'kind) yuanxu-module-import-kind)))
