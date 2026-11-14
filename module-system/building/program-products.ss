;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Pure projection of standard native target products; no compiler or loader.
(import (only-in :clan/poo/object .o .get .slot? .all-slots object?)
        (only-in :std/list/list find filter-map delete-duplicates/hash)
        (only-in :clan/poo/mop Type. define-type element?)
        (only-in :clan/poo/type List)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-name?))
(export make-target? StdMakeRowContract DefbuildScriptContract make-target-kind make-target-spec program-targets
        program-path program-identity? projection-program-targets)

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

(def (build-root? value)
  (or (and (string? value) (> (string-length value) 0))
      (and (list? value) (>= (length value) 2) (eq? (car value) 'gxc:)
           (string? (cadr value)) (> (string-length (cadr value)) 0)
           (andmap string? (cddr value)))))
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
