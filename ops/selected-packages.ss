;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Operational consumer of Core's selected external-package contributions.
;;; It does not compile Module sources or generate a defbuild-script.
(import :clan/poo/object
        (only-in :yuanxu/object-types/contracts yuanxu-validation-evidence-accepted?)
        (only-in :yuanxu/module-system/source/build unique-build-inputs)
        (only-in :yuanxu/module-system/source/admission module-source-type module-source-name?
                 module-source-read module-source-admit-current! call-with-module-source-read-cache
                 module-source-operation-resume
                 current-module-source-observer))
(export SelectedPackages.)
(def (package-stage name action)
  (def observer (current-module-source-observer))
  (if (not observer) (action)
    (dynamic-wind
      (lambda () (observer (list 'package-stage-start name) 1))
      action
      (lambda () (observer (list 'package-stage-end name) 1)))))
(def (forms-text forms)
  (call-with-output-string
    (lambda (port) (for-each (lambda (form) (write form port) (newline port)) forms))))
(def (write-input! path text)
  (create-directory* (path-directory path))
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def (check-output-path! path)
  ;; Refuse symlinks through every existing component, including the root.
  (let loop ((current path))
    (when (eq? (module-source-type current) 'symbolic-link)
      (error "Ops output path contains a symlink" current))
    (let (parent (path-directory (path-strip-trailing-directory-separator current)))
      (unless (equal? parent current) (loop parent)))))
(def (realize-selected-packages selection directory)
  (unless (and (object? selection) (string? directory))
    (error "selected package operation requires a selection and output directory"))
  (let* ((graph-value (.get selection build-graph))
         (requests (package-stage 'external-requests (lambda () (.get graph-value external-packages))))
         (output-root (path-expand directory))
         (entry-path (path-expand "guard.ss" output-root))
         (observed (package-stage 'source-inputs (lambda () (.get graph-value source-inputs)))))
    (unless (null? (.get graph-value other-projections))
      (error "unsupported selected operational projections" (.get graph-value other-projections)))
    ;; Source compiler entries remain owned by Core/std/make. This operation
    ;; consumes only external packages, retaining the whole graph's source guards.
    (package-stage 'entry-current (lambda () (.call graph-value admit-current)))
    (check-output-path! output-root)
    (when (and (file-exists? output-root) (pair? (directory-files output-root)))
      (error "Ops package output must be fresh" output-root))
    (def inputs
      (foldr append '()
        (map (lambda (request)
               (let* ((id (symbol->string (.get request identity)))
                      (seen (make-hash-table))
                      (destination (path-expand (string-append "external/" id) output-root)))
                 (unless (module-source-name? id) (error "invalid selected package identity" id))
                 (map (lambda (row)
                        (unless (and (pair? row) (string? (car row)) (string? (cdr row))
                                     (module-source-name? (car row)) (not (hash-key? seen (car row))))
                          (error "invalid selected package input" row))
                        (hash-put! seen (car row) #t)
                        (cons (path-expand (car row) destination) (cdr row)))
                      (.get request input-files)))) requests)))
    (def (inputs-current!)
      (call-with-module-source-read-cache
        (lambda ()
          (.call graph-value admit-current)
          (module-source-admit-current! observed)
          (module-source-admit-current! inputs))))
    (for-each (lambda (row) (write-input! (car row) (cdr row))) inputs)
    (package-stage 'inputs-current inputs-current!)
    (let* ((results
            (package-stage 'realize
             (lambda ()
              (map (lambda (request)
                   (cons (.get request identity)
                     (.call request .realize
                       (path-expand (string-append "external/" (symbol->string (.get request identity))) output-root)
                       inputs-current!))) requests))))
           (values (map cdr results))
           (script
            (package-stage 'guard-script
             (lambda () (forms-text
             `((import :gerbil/core :yuanxu/module-system/source/admission
                       ,@(foldr append '() (map (cut .get <> guard-imports) values)))
               ;; A normal operational guard, not a build specification.
               (def (main . arguments)
                 (unless (equal? arguments '("check")) (error "expected check"))
                 (module-source-admit-current! ',(unique-build-inputs (append observed inputs)))
                 ,@(foldr append '() (map (cut .get <> guard-forms) values))
                 #t))))))
           (entry-observation (list (cons entry-path script))))
      (def (sources-current!)
        (inputs-current!)
        (module-source-admit-current! entry-observation))
      (def (current!)
        (sources-current!)
        ;; May realize or evaluate Nix. Never share a source-read cache across it.
        (let loop ((remaining values) (inputs-checked? #t))
          (if (null? remaining)
            ;; A matched native tail has just checked inputs-current!. The
            ;; generated guard entry is a separate obligation and stays fresh.
            (if inputs-checked?
              (module-source-admit-current! entry-observation)
              (sources-current!))
            (let* ((value (car remaining))
                   (resume (module-source-operation-resume value inputs-current!)))
              (if (and inputs-checked? resume) (resume) (.call value admit-current))
              ;; Carry only a constructive native tail, never an opaque return
              ;; value. Recheck metadata without demand after the action: an
              ;; installed protocol/observer or invalidation ends the segment.
              (loop (cdr remaining)
                (and resume (module-source-operation-resume value inputs-current!) #t))))))
      (inputs-current!)
      (write-input! entry-path script)
      (package-stage 'value-admission
       (lambda () (for-each
        (lambda (value)
          (when (.slot? value 'admission)
            (unless (yuanxu-validation-evidence-accepted? (.get value admission))
              (error "external package configuration admission rejected")))) values)))
      ;; Admission may execute arbitrary validators. No candidate escapes until
      ;; every package identity and source is rechecked AFTER those validators.
      ;; Do not precheck and then treat a cached value receipt as currentness.
      (package-stage 'publication-current current!)
      (.o build-graph: graph-value packages: (object<-alist results)
          guard-entry: entry-path sources-current: sources-current!
          admit-current: current!))))
(.def (SelectedPackages. @ [])
  selection: #f
  directory: #f
  .run: (lambda () (realize-selected-packages selection directory)))
