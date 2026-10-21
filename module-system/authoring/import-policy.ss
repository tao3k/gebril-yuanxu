;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: reader-native policy for imports written inside a POO module role.
;;; Invariant: this owner reads datums only; it never expands or evaluates them.

(import (only-in :clan/poo/object .o .ref)
        (only-in :yuanxu/utilities/algorithms
                 yuanxu-read-datums/append-map
                 yuanxu-scheme-datum-find))

(export yuanxu-module-owner-import-observation-kind
        SourceInspectionPolicy.
        yuanxu-module-owner-import-datum-observations
        yuanxu-module-owner-import-port-observations
        yuanxu-module-owner-import-file-observations
        yuanxu-build-bootstrap-import-datum-observations
        yuanxu-build-bootstrap-import-port-observations
        yuanxu-build-bootstrap-import-file-observations
        yuanxu-build-bootstrap-datum-observations
        yuanxu-build-bootstrap-port-observations
        yuanxu-build-bootstrap-file-observations)


(def yuanxu-module-owner-import-observation-kind
  "yuanxu.module-owner-import-observation.v1")

;;; A consumer supplies repository policy as a native value. No product
;;; namespace, source directory or build frontend is inferred by Core.
(def SourceInspectionPolicy.
  (.o aggregate-imports: '()
      package-prefix: #f
      source-roots: '()
      forbidden-projections: '()))

(def (yuanxu-module-import-datum-first-member datum members)
  (yuanxu-scheme-datum-find
   (lambda (candidate)
     (and (symbol? candidate) (memq candidate members) candidate))
   datum))

(def (yuanxu-module-owner-import-observation scope owner)
  (list
   (cons 'kind yuanxu-module-owner-import-observation-kind)
   (cons 'scope scope)
   (cons 'owner owner)
   (cons 'form 'import)
   (cons 'phase 'module-admission)
   (cons 'status 'aggregate-owner-import)
   (cons 'detail
         (list
          (cons 'code 'module-owner-import-expands-aggregate-facade)
          (cons 'recommendation 'import-precise-owner)))
   (cons 'runtime-executed #f)))

;; : (-> Symbol SchemeDatum [Alist])
(def (yuanxu-module-owner-import-datum-observations scope datum (policy SourceInspectionPolicy.))
  (if (and (pair? datum) (eq? (car datum) 'import))
    (let (owner
          (yuanxu-module-import-datum-first-member
           (cdr datum)
           (.ref policy 'aggregate-imports)))
      (if owner
        (list (yuanxu-module-owner-import-observation scope owner))
        '()))
    '()))

;; : (-> Symbol InputPort [Alist])
(def (yuanxu-module-owner-import-port-observations scope port (policy SourceInspectionPolicy.))
  (yuanxu-read-datums/append-map
   (cut yuanxu-module-owner-import-datum-observations scope <> policy)
   port))

;; : (-> Symbol PathString [Alist])
(def (yuanxu-module-owner-import-file-observations scope path (policy SourceInspectionPolicy.))
  (call-with-input-file
   path
   (lambda (port)
     (yuanxu-module-owner-import-port-observations scope port policy))))

;;; A package build entry executes before its own artifacts exist. Importing a
;;; local package owner here creates a loaded-module/currentness cycle on
;;; macOS, where the compiler emits numbered replacement objects forever.
(def (yuanxu-build-bootstrap-package-owner datum policy)
  (yuanxu-scheme-datum-find
   (lambda (candidate)
     (cond
      ((string? candidate)
       (and (ormap (lambda (root) (string-prefix? root candidate))
                    (.ref policy 'source-roots))
            candidate))
      ((symbol? candidate)
       (and (.ref policy 'package-prefix)
            (string-prefix? (.ref policy 'package-prefix) (symbol->string candidate))
            candidate))
      (else #f)))
   datum))

(def (yuanxu-build-bootstrap-import-observation scope owner)
  (list
   (cons 'kind yuanxu-module-owner-import-observation-kind)
   (cons 'scope scope)
   (cons 'owner (if (string? owner) (string->symbol owner) owner))
   (cons 'form 'import)
   (cons 'phase 'build-bootstrap-admission)
   (cons 'status 'build-bootstrap-imports-package-owner)
   (cons 'detail
         (list
          (cons 'code 'build-bootstrap-self-import)
          (cons 'recommendation 'declare-package-spec-only)))
   (cons 'runtime-executed #f)))

(def (yuanxu-build-bootstrap-projection-form datum policy)
  (yuanxu-scheme-datum-find
   (lambda (candidate)
     (and (pair? candidate)
          (memq (car candidate)
                (.ref policy 'forbidden-projections))
          (car candidate)))
   datum))

(def (yuanxu-build-bootstrap-projection-observation scope form)
  (list
   (cons 'kind yuanxu-module-owner-import-observation-kind)
   (cons 'scope scope)
   (cons 'owner form)
   (cons 'form form)
   (cons 'phase 'build-bootstrap-admission)
   (cons 'status 'build-bootstrap-reimplements-package-projection)
   (cons 'detail
         (list
          (cons 'code 'build-bootstrap-parallel-projection)
          (cons 'recommendation 'declare-public-entry-modules)))
   (cons 'runtime-executed #f)))

(def (yuanxu-build-bootstrap-import-datum-observations scope datum (policy SourceInspectionPolicy.))
  (if (and (pair? datum) (eq? (car datum) 'import))
    (alet (owner (yuanxu-build-bootstrap-package-owner (cdr datum) policy))
      (list (yuanxu-build-bootstrap-import-observation scope owner)))
    '()))

(def (yuanxu-build-bootstrap-import-port-observations scope port (policy SourceInspectionPolicy.))
  (yuanxu-read-datums/append-map
   (cut yuanxu-build-bootstrap-import-datum-observations scope <> policy)
   port))

(def (yuanxu-build-bootstrap-import-file-observations scope path (policy SourceInspectionPolicy.))
  (call-with-input-file
   path
   (lambda (port)
     (yuanxu-build-bootstrap-import-port-observations scope port policy))))

;; : (-> Symbol SchemeDatum [Alist])
(def (yuanxu-build-bootstrap-datum-observations scope datum (policy SourceInspectionPolicy.))
  (append
   (or (yuanxu-build-bootstrap-import-datum-observations scope datum policy) '())
   (let (form (yuanxu-build-bootstrap-projection-form datum policy))
     (if form
       (list (yuanxu-build-bootstrap-projection-observation scope form))
       '()))))

;; : (-> Symbol InputPort [Alist])
(def (yuanxu-build-bootstrap-port-observations scope port (policy SourceInspectionPolicy.))
  (yuanxu-read-datums/append-map
   (cut yuanxu-build-bootstrap-datum-observations scope <> policy)
   port))

;; : (-> Symbol PathString [Alist])
(def (yuanxu-build-bootstrap-file-observations scope path (policy SourceInspectionPolicy.))
  (call-with-input-file
   path
   (lambda (port)
     (yuanxu-build-bootstrap-port-observations scope port policy))))
