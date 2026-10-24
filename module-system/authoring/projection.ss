;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Boundary: native POO projection of reader-owned authoring observations.
;;; Invariant: source datums are discarded before a public receipt is returned.

(import (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/module-system/authoring/observation
                 yuanxu-scheme-inline-prototype-datum-observations
                 yuanxu-scheme-inline-prototype-port-observations
                 yuanxu-scheme-inline-prototype-file-observations)
        (only-in :yuanxu/module-system/authoring/import-policy
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
        (only-in :yuanxu/observability/types YuanxuAuthoringObservationContract))

(export YuanxuAuthoringObservationContract
        yuanxu-authoring-inline-prototype-datum-observations
        yuanxu-authoring-inline-prototype-port-observations
        yuanxu-authoring-inline-prototype-file-observations
        yuanxu-authoring-owner-import-datum-observations
        yuanxu-authoring-owner-import-port-observations
        yuanxu-authoring-owner-import-file-observations
        yuanxu-authoring-build-bootstrap-import-datum-observations
        yuanxu-authoring-build-bootstrap-import-port-observations
        yuanxu-authoring-build-bootstrap-import-file-observations
        yuanxu-authoring-build-bootstrap-datum-observations
        yuanxu-authoring-build-bootstrap-port-observations
        yuanxu-authoring-build-bootstrap-file-observations
        yuanxu-authoring-observation-sexp)

;;; Resolve the stable Contract prototype once when this owner loads.  Receipt
;;; construction then exposes object composition as its only cold operation.
(def YuanxuAuthoringObservation.
  (.ref YuanxuAuthoringObservationContract 'proto))

;; : (-> Alist Symbol Value)
(def (yuanxu-authoring-row-ref row key)
  (let (entry (assq key row))
    (if entry
      (cdr entry)
      (error "missing source authoring observation field" key))))

;; : (-> Alist YuanxuAuthoringObservation)
(def (yuanxu-authoring-observation-from-row row)
  (let (detail (yuanxu-authoring-row-ref row 'detail))
    (validate YuanxuAuthoringObservationContract
      (.o (:: @ YuanxuAuthoringObservation.)
          scope: (yuanxu-authoring-row-ref row 'scope)
          owner: (yuanxu-authoring-row-ref row 'owner)
          form: (yuanxu-authoring-row-ref row 'form)
          phase: (yuanxu-authoring-row-ref row 'phase)
          status: (yuanxu-authoring-row-ref row 'status)
          code: (yuanxu-authoring-row-ref detail 'code)
          recommendation: (yuanxu-authoring-row-ref detail 'recommendation)
          accepted?: #f
          runtime-executed?: #f))))

;; : (-> [Alist] [YuanxuAuthoringObservation])
(def (yuanxu-authoring-observations-from-rows rows)
  (map yuanxu-authoring-observation-from-row rows))

;; : (-> Symbol Value [YuanxuAuthoringObservation])
(def (yuanxu-authoring-inline-prototype-datum-observations scope datum)
  (yuanxu-authoring-observations-from-rows
   (yuanxu-scheme-inline-prototype-datum-observations scope datum)))

;; : (-> Symbol InputPort [YuanxuAuthoringObservation])
(def (yuanxu-authoring-inline-prototype-port-observations scope port)
  (yuanxu-authoring-observations-from-rows
   (yuanxu-scheme-inline-prototype-port-observations scope port)))

;; : (-> Symbol PathString [YuanxuAuthoringObservation])
(def (yuanxu-authoring-inline-prototype-file-observations scope path)
  (yuanxu-authoring-observations-from-rows
   (yuanxu-scheme-inline-prototype-file-observations scope path)))

;; : (-> Symbol SchemeDatum [YuanxuAuthoringObservation])
(def (yuanxu-authoring-owner-import-datum-observations scope datum (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-module-owner-import-datum-observations scope datum policy)))

;; : (-> Symbol InputPort [YuanxuAuthoringObservation])
(def (yuanxu-authoring-owner-import-port-observations scope port (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-module-owner-import-port-observations scope port policy)))

;; : (-> Symbol PathString [YuanxuAuthoringObservation])
(def (yuanxu-authoring-owner-import-file-observations scope path (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-module-owner-import-file-observations scope path policy)))

(def (yuanxu-authoring-build-bootstrap-import-datum-observations scope datum (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-build-bootstrap-import-datum-observations scope datum policy)))

(def (yuanxu-authoring-build-bootstrap-import-port-observations scope port (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-build-bootstrap-import-port-observations scope port policy)))

(def (yuanxu-authoring-build-bootstrap-import-file-observations scope path (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-build-bootstrap-import-file-observations scope path policy)))

(def (yuanxu-authoring-build-bootstrap-datum-observations scope datum (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-build-bootstrap-datum-observations scope datum policy)))

(def (yuanxu-authoring-build-bootstrap-port-observations scope port (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-build-bootstrap-port-observations scope port policy)))

(def (yuanxu-authoring-build-bootstrap-file-observations scope path (policy SourceInspectionPolicy.))
  (yuanxu-authoring-observations-from-rows
   (yuanxu-build-bootstrap-file-observations scope path policy)))

;;; The final projection is closed over symbolic fields and cannot reconstruct
;;; the discarded source datum or claim runtime execution.
;; : (-> YuanxuAuthoringObservation Sexp)
(def (yuanxu-authoring-observation-sexp observation)
  (validate YuanxuAuthoringObservationContract observation)
  (list 'poo-authoring-observation
        (list 'scope (.ref observation 'scope))
        (list 'owner (.ref observation 'owner))
        (list 'form (.ref observation 'form))
        (list 'phase (.ref observation 'phase))
        (list 'status (.ref observation 'status))
        (list 'code (.ref observation 'code))
        (list 'recommendation (.ref observation 'recommendation))
        (list 'accepted? (.ref observation 'accepted?))
        (list 'runtime-executed? (.ref observation 'runtime-executed?))))
