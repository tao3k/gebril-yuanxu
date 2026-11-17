;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure projection of standard native target products; no compiler or loader.
(import (only-in :clan/poo/object .o .get .slot? .all-slots object?)
        (only-in :std/list/list find filter-map delete-duplicates/hash)
        (only-in :std/string/path path-absolute?)
        (only-in :clan/poo/type Type. define-type element? List)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-name? module-source-type module-source-read))
(export make-target? resolve-make-target-inputs StdMakeRowContract DefbuildScriptContract ModuleBuildContract make-target-kind make-target-spec program-targets
        program-path program-identity? projection-program-targets module-build-ffi-targets)

(def (make-target-kind entry)
  (if (.slot? entry 'make-kind) (.get entry make-kind) 'gxc:))

(def (make-target-spec entry name)
  (if (eq? (make-target-kind entry) 'exe:)
    `(exe: ,name bin: ,(.get entry bin-name) ,@(.get entry options))
    `(gxc: ,name ,@(.get entry options))))

(def (program-targets entries)
  (def programs
    (filter-map
    (lambda (entry)
      (and (eq? (make-target-kind entry) 'exe:)
           (.o compiler-identity: (.get entry compiler-identity)
               bin-name: (.get entry bin-name)))) entries))
  (def names (map (lambda (program) (.get program bin-name)) programs))
  (unless (= (length names) (length (delete-duplicates/hash names)))
    (error "programs share one binary output" names))
  programs)

(def (projection-program-targets projection)
  (if (.slot? projection 'program-targets) (.get projection program-targets) '()))

(def (program-identity? identity programs)
  (find (lambda (program) (eq? (.get program compiler-identity) identity)) programs))

(def (program-path program libdir)
  (path-expand (.get program bin-name) (path-expand "bin" libdir)))

;; std/make treats the first list after a gxc: target name as target
;; properties. Keep the extra-inputs row intact all the way to Make.
(def (make-library-options? options)
  (match options
    ([[extra-inputs: (? list? inputs)] . flags]
     (and (andmap (lambda (input) (and (string? input) (> (string-length input) 0))) inputs)
          (andmap string? flags)))
    (else (andmap string? options))))

;; Make runs relative to the package root, even when the declaration lives
;; under a Module. Bind relative dependencies to that same physical root.
(def (resolve-make-target-inputs target root observe!)
  (match target
    ([gxc: name [extra-inputs: inputs] . options]
     (def (observe input)
       (unless (and (not (path-absolute? input))
                    (andmap module-source-name? (string-split input #\/)))
         (error "Make extra input must be package-relative" input))
       (let walk ((directory root) (parts (string-split input #\/)))
         (let ((path (path-expand (car parts) directory))
               (more (cdr parts)))
           (unless (eq? (module-source-type path) (if (null? more) 'regular 'directory))
             (error "Make extra input is missing, non-regular or a symlink" path))
           (if (null? more)
               (let (file (path-normalize path))
                 (observe! (cons file (module-source-read file)))
                 file)
               (walk path more)))))
     [gxc: name [extra-inputs: (map observe inputs)] options ...])
    (else target)))

(def (build-root? value)
  (or (and (string? value) (> (string-length value) 0))
      (and (list? value) (>= (length value) 2) (eq? (car value) 'gxc:)
           (string? (cadr value)) (> (string-length (cadr value)) 0)
           (make-library-options? (cddr value)))))
;; Executables are native Make products, not test-only demands. Their source
;; ownership and currentness are checked by the enclosing projection.
(def (make-target? value)
  (or (build-root? value)
      (and (list? value) (>= (length value) 2) (eq? (car value) 'exe:)
           (string? (cadr value)) (> (string-length (cadr value)) 0)
           (let (options (cddr value))
             (if (and (pair? options) (eq? (car options) 'bin:))
               (and (pair? (cdr options)) (string? (cadr options))
                    (module-source-name? (cadr options)) (andmap string? (cddr options)))
               (andmap string? options))))))
(define-type (StdMakeRowContract @ Type.)
  identity: 'module/std-make-row .element?: make-target?)

(def StdMakeRows (List StdMakeRowContract))

;; The module role supplies Make's positional spec. The package entry owns
;; keyword settings such as output directories and the package prefix.
(define-type (DefbuildScriptContract @ Type.)
  identity: 'module/defbuild-script
  .element?: (lambda (parameters)
    (and (object? parameters)
         (equal? (.all-slots parameters) '(spec))
         (element? StdMakeRows (.get parameters spec)))))

;; Build is a POO object, so an inherited Build supplies the same effective
;; parameter slot as a directly defined Build.
(define-type (ModuleBuildContract @ Type.)
  identity: 'module/build
  .element?: (lambda (build)
               (and (object? build) (.slot? build 'defbuild-script)
                    (let (script (.get build defbuild-script))
                      (and (element? DefbuildScriptContract script)
                           (or (not (.slot? build 'ffi))
                               (let (targets (.get build ffi))
                                 (and (list? targets)
                                      (andmap build-root? targets)
                                      (null? (filter (cut member <> (.get script spec)) targets))))))))))

(def (module-build-ffi-targets build)
  (if (.slot? build 'ffi) (.get build ffi) '()))
