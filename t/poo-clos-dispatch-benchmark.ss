;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Repeatable hot-call witness: one-method and wide inapplicable method sets.
;;; The source-role workload pairs real stock and Generic authoring admissions.

(import (only-in :clan/poo/object .o .get)
        (only-in :gerbil/runtime/gambit current-jiffy jiffies-per-second)
        (only-in :clan/poo/mop clos-add-method clos-call
                 clos-compute-applicable-methods clos-generic-function
                 clos-method clos-prototype-specializer)
        (only-in :clan/poo/object/read-projection call-with-owned-source-reads)
        (only-in :clan/poo/type Record)
        (only-in :tao3k/yuanxu/module-system/source/interface
                 yuanxu-module-interface yuanxu-module-interface-authoring)
        (only-in :tao3k/yuanxu/module-system/authoring/admission
                 ModuleAuthoringAnalysisGeneric call-with-module-authoring-read-scope
                 yuanxu-module-authoring-role yuanxu-module-authoring-source-admit))

(def +iterations+ 2000)

(def (make-case method-count)
  (let* ((target (.o))
         (argument (.o (:: @ target))))
    (let loop ((index 0)
               (generic (clos-generic-function 'dispatch-benchmark 1)))
      (if (= index method-count)
        (values generic argument)
        (let ((prototype (if (= index (- method-count 1)) target (.o))))
          (loop (+ index 1)
                (clos-add-method
                 generic
                 (clos-method
                  (string->symbol
                   (string-append "method-" (number->string index)))
                  (list (clos-prototype-specializer prototype))
                  (lambda (_frame _argument) index)))))))))

(def (measure label thunk expected)
  (unless (= (thunk) expected)
    (error "dispatch benchmark semantic mismatch" label))
  (let warm ((index 0))
    (when (< index 100)
      (thunk)
      (warm (+ index 1))))
  (let ((start (current-jiffy)))
    (let run ((index 0) (last #f))
      (if (= index +iterations+)
        (begin
          (unless (= last expected)
            (error "dispatch benchmark result drift" label))
          (display label) (display "-ms-per-1000=")
          (display
           (/ (* (- (current-jiffy) start) 1000000)
              (* (jiffies-per-second) +iterations+)))
          (newline))
        (run (+ index 1) (thunk))))))

(def (benchmark-dispatch)
  (display "schema=core.poo-clos-dispatch.v1\n")
  (display "iterations=") (display +iterations+) (newline)
  (let-values (((generic argument) (make-case 1)))
    (measure "single-call"
             (lambda () (clos-call generic argument)) 0)
    (measure "single-applicable"
             (lambda ()
               (length (clos-compute-applicable-methods generic argument))) 1))
  (let-values (((generic argument) (make-case 64)))
    (measure "wide-call"
             (lambda () (clos-call generic argument)) 63)
    (measure "wide-applicable"
             (lambda ()
               (length (clos-compute-applicable-methods generic argument))) 1)))

(def (run-admission-sample action count)
  (##gc)
  (let (before (##process-statistics))
    (let loop ((remaining count))
      (unless (zero? remaining)
        (unless (action) (error "source role admission changed"))
        (loop (1- remaining))))
    (let (after (##process-statistics))
      (unless (= (f64vector-length before) (f64vector-length after) 20)
        (error "unsupported Gambit statistics layout"))
      (def (delta index) (- (f64vector-ref after index) (f64vector-ref before index)))
      (values (+ (delta 0) (delta 1)) (delta 6)
              (- (delta 7) (f64vector-ref after 9))))))

(def (source-role-sample name action)
  (def repetitions 128)
  (def batch-size 8)
  (defvalues (cpu collections _) (run-admission-sample action repetitions))
  ;; Counter 7 is comparable within a no-GC interval only. Smaller untimed
  ;; batches cover the same admissions without borrowing that CPU sample.
  (def allocation
    (let loop ((remaining repetitions) (bytes 0))
      (if (zero? remaining) bytes
        (let-values (((_ collections allocated) (run-admission-sample action batch-size)))
          (and (zero? collections) (>= allocated 0)
               (loop (- remaining batch-size) (+ bytes (inexact->exact allocated))))))))
  (write (list 'source-role name repetitions 'cpu-seconds cpu 'collections collections
               'allocated-bytes allocation))
  (newline)
  (force-output))

(def (benchmark-source-role)
  (def interface (yuanxu-module-interface "source-role-stock" (Record) '()))
  (def datums '((def First 1) (def Second 2) (def Third 3)))
  (def executor (.get (yuanxu-module-interface-authoring interface) executor))
  (def role (yuanxu-module-authoring-role interface 'objects))
  (def (stock)
    (call-with-owned-source-reads void
      (lambda ()
        (let-values (((accepted diagnostic)
                      (yuanxu-module-authoring-source-admit interface 'objects datums)))
          (and accepted (not diagnostic))))))
  (def (generic)
    (andmap (lambda (datum)
              (call-with-module-authoring-read-scope
                (lambda ()
                  (null? (clos-call ModuleAuthoringAnalysisGeneric executor role interface datum)))))
            datums))
  (unless (and (stock) (generic)) (error "source role benchmark setup rejected"))
  (display "schema=core.poo-clos-source-role.v1\n")
  (source-role-sample 'stock stock)
  (source-role-sample 'generic generic)
  (source-role-sample 'generic generic)
  (source-role-sample 'stock stock))

(match (command-line)
  ([_ _] (benchmark-dispatch))
  ([_ _ "dispatch"] (benchmark-dispatch))
  ([_ _ "source-role"] (benchmark-source-role))
  (arguments (error "unknown dispatch benchmark workload" arguments)))
(display "accepted=#t\n")
