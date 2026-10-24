;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Source-neutral Module diagnostic and DoctorReport POO values. Product
;;; owners decide which facts are findings and how to present them.

(import (only-in :yuanxu/object-family/syntax defpoo-object-family)
        (only-in :std/list/list any))

(export yuanxu-module-diagnostic-prototype
        make-yuanxu-module-diagnostic
        yuanxu-module-diagnostic?
        yuanxu-module-diagnostic-severity
        yuanxu-module-diagnostic-code
        yuanxu-module-diagnostic-target
        yuanxu-module-diagnostic-detail
        yuanxu-module-diagnostics-status
        yuanxu-module-doctor-report-prototype
        make-yuanxu-module-doctor-report
        yuanxu-module-doctor-report?
        yuanxu-module-doctor-report-modules
        yuanxu-module-doctor-report-status
        yuanxu-module-doctor-report-diagnostics
        yuanxu-module-doctor-ok?)

(defpoo-object-family
  (prototype yuanxu-module-diagnostic-prototype
             module-diagnostic?
             yuanxu-module-diagnostic?)
  (constructor make-yuanxu-module-diagnostic
               (severity-value severity)
               (code-value code)
               (target-value target)
               (detail-value detail))
  (accessors
   (yuanxu-module-diagnostic-severity severity)
   (yuanxu-module-diagnostic-code code)
   (yuanxu-module-diagnostic-target target)
   (yuanxu-module-diagnostic-detail detail))
  (projections))

(def (yuanxu-module-diagnostics-status diagnostics)
  (cond
   ((any (lambda (diagnostic)
           (eq? (yuanxu-module-diagnostic-severity diagnostic) 'error))
         diagnostics)
    'error)
   ((pair? diagnostics) 'warning)
   (else 'ok)))

(defpoo-object-family
  (prototype yuanxu-module-doctor-report-prototype
             module-doctor-report?
             yuanxu-module-doctor-report?)
  (constructor make-yuanxu-module-doctor-report
               (modules-value modules)
               (status-value status)
               (diagnostics-value diagnostics))
  (accessors
   (yuanxu-module-doctor-report-modules modules)
   (yuanxu-module-doctor-report-status status)
   (yuanxu-module-doctor-report-diagnostics diagnostics))
  (projections))

(def (yuanxu-module-doctor-ok? report)
  (eq? (yuanxu-module-doctor-report-status report) 'ok))
