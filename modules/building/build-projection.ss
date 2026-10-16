;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Build-tool entry, not a Module runtime Loader. std/build-script + std/make
;;; own native import dependencies, scheduling, compilation and incremental work.
(import (only-in :std/string/path path-absolute?)
        (only-in :clan/poo/object .o .ref)
        (only-in :core/module-system/interface poo-flow-load-modules)
        (only-in :core/module-system/source/admission module-source-type module-source-read module-source-name?))
(export poo-flow-core-write-build-entry poo-flow-core-admit-build-inputs)
(def (poo-flow-core-admit-build-inputs observations)
  ;; Serialized compiler-input receipt. Selection must be regenerated if any
  ;; observed input changes; it is never a runtime execution authorization.
  (for-each
   (lambda (entry)
     (unless (if (cdr entry)
               (and (eq? (module-source-type (car entry)) 'regular)
                    (equal? (cdr entry) (module-source-read (car entry))))
               (not (module-source-type (car entry))))
       (error "stale selected build input; regenerate the build entry" (car entry)))) observations))
(def (forms-text forms)
  (call-with-output-string
   (lambda (port)
     (display ";;; Generated selected Graph compiler input; do not edit.\n" port)
     (for-each (lambda (form) (write form port) (newline port)) forms))))
(def (admit-artifact-path! root relative)
  (let walk ((directory root) (parts (string-split relative #\/)))
    (let (kind (module-source-type directory))
      (unless (or (not kind) (eq? kind 'directory))
        (error "build artifact directory is non-directory or a symlink" directory)))
    (when (pair? (cdr parts)) (walk (path-expand (car parts) directory) (cdr parts)))))
(def (write-input! path text)
  (cond
   ((not (module-source-type path))
    (create-directory* (path-directory path))
    (call-with-output-file (list path: path create: #t)
      (lambda (port) (display text port))))
   ((and (eq? (module-source-type path) 'regular) (equal? text (module-source-read path))) (void))
   (else (error "build artifact already exists with different input" path))))
(def (poo-flow-core-write-build-entry source output-directory read-publication: (reader #f))
  (unless (and (string? output-directory) (path-absolute? output-directory))
    (error "build artifact directory must be absolute" output-directory))
  (let* ((view (if (string? source) (poo-flow-load-modules source read-publication: reader) source))
         (graph (.ref view 'build-graph))
         (entries (.ref graph 'entries))
         (targets (make-hash-table))
         (spec
          (map
           (lambda (entry)
             (let* ((id (symbol->string (.ref entry 'compiler-identity)))
                    (target (path-expand (string-append id ".ss") output-directory)))
               (unless (andmap module-source-name? (string-split id #\/))
                 (error "compiler identity is not a relative build target" id))
               (let (key (string-downcase id))
                 (when (or (string=? key "build") (hash-key? targets key)) (error "case-colliding compiler build targets" id))
                 (hash-put! targets key #t))
               (admit-artifact-path! output-directory (string-append id ".ss"))
               (list entry target `(gxc: ,id ,@(.ref entry 'options))))) entries)))
    ((.ref graph 'admit-current))
    (admit-artifact-path! output-directory "build.ss")
    (when (and (eq? (module-source-type output-directory) 'directory)
               (not (module-source-type (path-expand "build.ss" output-directory)))
               (pair? (directory-files output-directory)))
      (error "build artifact directory is not empty or owned by a selected build entry" output-directory))
    ;; Validate every destination before writing any input. No source is replaced.
    (let* ((files
            (map (lambda (row)
                   (cons (cadr row) (forms-text (.ref (.ref (car row) 'input) 'compiler-forms)))) spec))
           (native-spec (map caddr spec))
           (entry-path (path-expand "build.ss" output-directory))
           (artifact-inputs (cons (cons (path-expand "gerbil.pkg" output-directory) #f) files))
           (script (forms-text
                    `((import :std/build-script :core/modules/building/build-projection)
                      ;; Identity-qualified targets under this generated srcdir.
                      ;; No artifact gerbil.pkg: std/make uses no extra prefix.
                      (defbuild-script
                        (begin (poo-flow-core-admit-build-inputs ',(append (.ref graph 'source-inputs) artifact-inputs)) ',native-spec))))))
      (def (artifact-current!)
        ((.ref graph 'admit-current))
        (poo-flow-core-admit-build-inputs (cons (cons entry-path script) artifact-inputs)))
      (poo-flow-core-admit-build-inputs (list (car artifact-inputs)))
      (for-each
       (lambda (file)
         (let (kind (module-source-type (car file)))
           (unless (or (not kind) (and (eq? kind 'regular) (equal? (cdr file) (module-source-read (car file)))))
             (error "build artifact already exists with different input" (car file)))))
       (cons (cons entry-path script) files))
      ((.ref graph 'admit-current))
      (for-each (lambda (file) (write-input! (car file) (cdr file))) files)
      (write-input! entry-path script)
      ((.ref graph 'admit-current))
      (.o selected-graph: (.ref graph 'selected-graph) build-graph: graph
          source-root: output-directory build-entry: entry-path spec: native-spec
          admit-current: artifact-current!))))
