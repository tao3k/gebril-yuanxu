;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Maintain exact source preparations and transfer admitted role contexts.
(import (only-in :clan/poo/object .cc .ref .ref/cached object?
                 object-%instance object-construction-current?)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :clan/poo/slot-observation without-observation)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        :yuanxu/module-system/source/admission
        :yuanxu/module-system/source/preparation
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/source/reader-session
        :yuanxu/module-system/source/reader-support
        :yuanxu/module-system/source/compiler-tools
        (only-in :yuanxu/module-system/source/role-context transfer-role-context)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module))
(export reader-enroll-candidate! reader-capture-input reader-input-origin
        reader-bind-input-state reader-input-state-current? reader-source-state-current?
        reader-add-input-guard! reader-derived-input reader-preparation-key
        reader-prepare-publication reader-check-preparation-policy!
        reader-prepare-public-dependency reader-for-each-kernel-context reader-transfer-context)

(def (reader-enroll-candidate! session guard)
  (when ((reader-session-candidate session))
    (set! (candidate-support-guards ((reader-session-candidate session)))
      (cons (if (source-preparation? guard) guard
                (make-source-preparation #f #f #f #f guard #f #f))
            (candidate-support-guards ((reader-session-candidate session)))))))
(def (reader-capture-input session value checker path ready? state (kind 'origin))
  (def origin (capture-source-preparation value checker path ready? state))
  (if (eq? kind 'origin)
    ;; Reuse the existing eq? input index. Runtime Context keys map to
    ;; inputs; POO input keys map to their actual constructor association.
    (hash-put! (reader-session-kernel-inputs session) value origin)
    ;; Derived copies are bounded by path here. Link binds their exact
    ;; association before a later derivation can replace this last view.
    (hash-put! (reader-session-preparations session) (list 'derived (path-normalize path)) origin))
  value)
(def (reader-input-origin session input (known-path #f))
  (and (object? input)
    (or (hash-get (reader-session-kernel-inputs session) input)
        (let (path
               (or known-path
                   (and (object-%instance input)
                     (begin
                       (require-read-route! 'source-preparation #f (object-%instance input))
                       (.ref/cached input 'path (lambda () #f))))))
          (and (string? path)
            (or (let (origin (hash-get (reader-session-preparations session) (list 'derived (path-normalize path))))
                  (and origin (eq? input (source-preparation-value origin)) origin))
                (let (context (hash-get (reader-session-tool-paths session) (path-normalize path)))
                  (and context (hash-get compiler-tool-inputs context)))))))))
(def (reader-bind-input-state session input (path #f))
  (with-catch (lambda (_unsupported) #f)
    (lambda ()
      (without-observation
        (lambda ()
          (let (origin (reader-input-origin session input path))
            (and origin (eq? input (source-preparation-value origin))
                 (source-preparation-checker origin)
                 (lambda ()
                   (and (not (reader-session-refused? session)) (object-construction-current?)
                        (source-preparation-current? origin))))))))))
(def (reader-input-state-current? session input)
  (and (owned-read-function-scope?) (not (current-module-source-observer))
   (with-catch (lambda (_unsupported) #f)
    (lambda ()
      (without-observation
        (lambda ()
          (and (object-construction-current?)
               (let (origin (reader-input-origin session input))
                 (and origin (eq? input (source-preparation-value origin))
                      (source-preparation-current? origin))))))))))
(def (reader-source-state-current? session)
  (and (owned-read-function-scope?) (not (current-module-source-observer))
   (with-catch (lambda (_unsupported) #f)
    (lambda ()
      (without-observation
        (lambda ()
          (and (not (reader-session-refused? session)) (object-construction-current?)
               (andmap source-preparation-current? (reader-session-guards session)))))))))
(def (reader-add-input-guard! session input (public-path #f))
  (def invoke (.ref input 'admit-current))
  (def origin (or (without-observation (lambda () (reader-input-origin session input)))
                   (make-source-preparation input #f #f #f #f #f #f)))
  (set! (source-preparation-invoke origin) invoke)
  (set! (source-preparation-public-path origin) public-path)
  (set! (reader-session-guards session) (cons origin (reader-session-guards session)))
  origin)
(def (reader-derived-input session prepared source (related #f))
  (def origin (without-observation (lambda () (reader-input-origin session prepared))))
  (def checker (and (reader-input-state-current? session prepared) (source-preparation-checker origin)))
  (def intact? (object-construction-current?))
  (def value (if related (.cc prepared 'source source 'source-dependencies related)
                 (.cc prepared 'source source)))
  (def actual (and intact? (object-construction-current?) checker))
  (def ready? (and origin (source-preparation-ready? origin)))
  (reader-capture-input session value actual (yuanxu-module-source-ref-value source) ready?
                 (and actual (module-source-input-state value actual ready?)) 'derived))
;; Reuse inert role/header projections within this reader's source epoch.
;; current! below checks the retained byte/package guards before EVERY use.
;; This does not retain an evaluated publication or skip macro/initializer
;; execution. Fresh SourceRef provenance is attached to the returned view.
(def (reader-preparation-key session source)
  (unless (yuanxu-module-source-ref? source)
    (error "publication preparation requires a SourceRef" source))
  (let (metadata (yuanxu-module-source-ref-metadata source))
    (cons (yuanxu-module-source-ref-kind source)
                (cons (path-normalize (yuanxu-module-source-ref-value source))
                  (map (lambda (name) (assq name metadata))
                       '(module-id module-root module-tree-root))))))
(def (reader-prepare-publication session source)
  (let* ((key (reader-preparation-key session source))
         (previous (hash-get (reader-session-preparations session) key)))
    (when (current-module-source-observer)
      ((current-module-source-observer) 'publication-preparation-requests 1))
    (if previous
      (begin (reader-check-preparation-policy! session previous) (reader-derived-input session previous source))
      (let (value
             (begin
               (when (current-module-source-observer)
                 ((current-module-source-observer) 'publication-policy-checks 1))
               (yuanxu-prepare-module-publication source capture: (cut reader-capture-input session <...>))))
        (when (current-module-source-observer)
          ((current-module-source-observer) 'publication-preparation-walks 1))
        (hash-put! (reader-session-preparations session) key value)
        (set! (reader-session-publication-prepared-count session) (+ (reader-session-publication-prepared-count session) 1))
        (reader-add-input-guard! session value)
        value))))
(def (reader-check-preparation-policy! session prepared)
  ;; Never cache authoring admission: MOP policy objects may change without
  ;; changing source bytes. Recheck the actual policy before using syntax.
  (let* ((source (.ref prepared 'source))
         (metadata (yuanxu-module-source-ref-metadata source))
         (owner (cdr (assq 'module-id metadata)))
         (root (cdr (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
         (policy yuanxu-default-module-style-policy))
    (when (current-module-source-observer)
      ((current-module-source-observer) 'publication-policy-checks 1))
    ((.ref policy 'validate) policy owner root module-source-read)
    ;; A policy is an author-code boundary, not a source-cache window.
    ((.ref prepared 'admit-current))))
(def (reader-prepare-public-dependency session path)
  ;; The SAME preparation owns source bytes and its original public binding.
  ;; On a hit run that original checker; do not recapture a changed ambient
  ;; name as a new successful identity. Compiler association remains scoped.
  (def key (list 'public-source path))
  (def previous (hash-get (reader-session-preparations session) key))
  (when (current-module-source-observer)
    ((current-module-source-observer) 'public-preparation-requests 1))
  (if previous
    (begin
      ((source-preparation-invoke previous))
      (reader-enroll-candidate! session previous)
      (source-preparation-value previous))
    (let* ((binding #f)
           (input (public-dependency-input path capture: (cut reader-capture-input session <...>)
                    bind: (lambda (value) (set! binding value)))))
      (when input
        (let (origin (reader-add-input-guard! session input path))
          (set! (source-preparation-invoke origin)
            (lambda ()
              (unless (public-dependency-input path input #t binding: binding)
                (error "public dependency source or runtime identity changed" path))))
          (hash-put! (reader-session-preparations session) key origin)
          (reader-enroll-candidate! session origin)
          (set! (reader-session-public-prepared-count session) (+ (reader-session-public-prepared-count session) 1)))
        (when (current-module-source-observer)
          ((current-module-source-observer) 'public-preparation-walks 1)))
      input)))
;; Project from the retained runtime graph into this publication's existing
;; input index. Do not retain a transitive context list for every root: on
;; overlapping/deep graphs those lists duplicate already-owned references.
;; Registration can grow, so resolve kernel-inputs afresh on EVERY visit.
(def (reader-for-each-kernel-context session context visit)
  (when (current-module-source-observer)
    ((current-module-source-observer) 'kernel-closure-requests 1)
    ((current-module-source-observer) 'kernel-closure-walks 1))
  (module-source-measure-operation 'reader-private-closure
   (lambda () (for-each-build-module context
    (lambda (child)
      (when (current-module-source-observer)
        ((current-module-source-observer) 'kernel-context-visits 1))
      ;; Canonical tools keep their complete separate source support.
      ;; Unknown contexts must still be traversed before filtering.
      (unless (captured-tool-context? (reader-session-compiler-contexts session) child)
        (visit child)))
    (make-hash-table-eq)
    (lambda (child)
      (not (captured-tool-context? (reader-session-compiler-contexts session) child)))))))
(def (reader-transfer-context session path owner-at available? install! tool?)
  (transfer-role-context (hash-get (reader-session-kernel-contexts session) path)
    (cut reader-for-each-kernel-context session <...>)
    (lambda (child)
      (values (hash-get (reader-session-kernel-inputs session) child)
              (hash-get (reader-session-kernel-owners session) child)
              (or (hash-get (reader-session-kernel-data session) child) '())
              (hash-get (reader-session-kernel-initializers session) child)))
    owner-at tool? available? install!
    (lambda (reason)
      (when (current-module-source-observer)
        ((current-module-source-observer)
          (list 'reader-context-not-transferred path reason) 1)))))
