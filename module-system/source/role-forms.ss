;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Gerbil-only role discovery shared by publication preparation and expansion.
(export yuanxu-module-allowed-entrypoint-roles yuanxu-module-required-role-files
        module-role-file module-publication-role-imports
        module-regular-role-file? module-init-export-name module-interface-form?)

;; A Gerbil facade re-exports directly imported files within its directory.
;; A Yuanxu Interface declares its publication with exactly one .def.
(def (module-interface-form? form forms)
  (def (imported-file? file)
    (and (string? file) (string=? (path-extension file) ".ss")
         (andmap (lambda (part) (not (member part '("" "." ".."))))
                 (string-split file #\/))
         (not (string=? file "interface.ss"))
         (ormap (lambda (input)
                  (and (list? input) (pair? input) (eq? (car input) 'import)
                       (member file (cdr input))))
                forms)))
  (and (pair? form) (list? form)
       (case (car form)
         ((import .def) #t)
         ((export)
          (and (pair? (cdr form))
               (andmap
                 (lambda (spec)
                   (and (list? spec) (pair? spec) (eq? (car spec) 'import:)
                        (pair? (cdr spec)) (andmap imported-file? (cdr spec))))
                 (cdr form))))
         (else #f))))

;; Runtime owner identity is metadata, not selection or object construction.
(def (module-init-export-name identity)
  (unless (symbol? identity) (error "init requires a runtime module identity" identity))
  (let (name (symbol->string identity))
    (let (separator (string-rindex name #\/))
      (string->symbol
        (string-append
          (if separator
            (string-append (substring name 0 separator) "."
                           (substring name (+ separator 1) (string-length name)))
            name)
          ".exports")))))
(def yuanxu-module-allowed-entrypoint-roles '(types objects func config interface build))
(def (module-role-file role)
  (string-append (symbol->string role) ".ss"))
(def yuanxu-module-required-role-files
  (map module-role-file '(types objects config interface)))
(def (module-publication-role-imports root present?)
  (filter-map
    (lambda (role)
      (and (memq role '(types func objects config))
           (let (name (module-role-file role))
             (and (present? (path-expand name root)) (string-append "./" name)))))
    yuanxu-module-allowed-entrypoint-roles))
(def (module-regular-role-file? path)
  (with-catch
    (lambda (e) (if (no-such-file-or-directory-exception? e) #f (raise e)))
    (lambda ()
      (unless (eq? (file-info-type (file-info path #f)) 'regular)
        (error "Module role is non-regular or a symlink" path))
      #t)))

;; The same literal declaration grammar serves the expander and the source
;; reader. Only the runtime reader needs selection objects.
(export init-name? parse-module-init module-init-mounts)

(def (init-name? name)
  (and (symbol? name)
       (let (text (symbol->string name))
         (and (> (string-length text) 0) (not (member text '("." "..")))
              (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list text))))))
(def (parse-init-window body source-path (window? #f))
  (def mount-value #f)
  (def profile-value #f)
  (def package-value #f)
  (def seen (make-hash-table-eq))
  (let parse ((tail body) (mode-value 'explicit) (root-value "modules")
              (group #f) (rows '()) (options '()))
    (cond
     ((null? tail)
      (unless (memq 'mode: options)
        (error "init.ss requires mode: explicit or mode: auto" source-path))
      (when profile-value
        (unless (and (eq? mode-value 'auto) (memq 'source: options))
          (error "profile selection requires source and auto mode" source-path)))
      (when package-value
        (unless (and (not (char=? (string-ref root-value 0) #\/))
                     (andmap (lambda (part)
                               (and (> (string-length part) 0)
                                    (not (member part '("." "..")))
                                    (not (string-index part #\\))
                                    (not (string-index part #\:))))
                             (string-split root-value #\/)))
          (error "package window requires a confined relative source" root-value)))
      [mode-value root-value mount-value profile-value
       (and (memq 'source: options) #t) (reverse rows) package-value])
     ((not (pair? tail)) (error "improper init declaration" source-path))
     ((memq (car tail) '(mode: source: rename: profile: package:))
      (unless (and (pair? (cdr tail)) (not group) (null? rows) (not (memq (car tail) options)))
        (error "duplicate or misplaced init option" (car tail) source-path))
      (let ((key (car tail)) (value (cadr tail)))
        (case key
          ((mode:) (unless (memq value '(auto explicit)) (error "invalid init mode" value)))
          ((source:) (unless (and (string? value) (> (string-length value) 0))
                       (error "invalid init source" value)))
          ((package:)
           (unless (and (string? value)
                        (= (length (string-split value #\/)) 3)
                        (andmap (lambda (part)
                                  (and (> (string-length part) 0)
                                       (init-name? (string->symbol part))
                                       (not (string-index part #\@))))
                                (string-split value #\/)))
             (error "package window requires a native repository identity without a tag" value))
           (set! package-value value))
          ((profile:)
           (unless (init-name? value) (error "profile: requires a literal name" value))
           (set! profile-value value))
          ((rename:)
           (unless (and window? (or (string? value) (symbol? value)))
             (error "rename requires a literal directory mount" value))
           (set! mount-value (if (string? value) (string->symbol value) value))))
        (parse (cddr tail) (if (eq? key 'mode:) value mode-value)
                 (if (eq? key 'source:) value root-value) group rows (cons key options))))
     ((and (symbol? (car tail))
           (> (string-length (symbol->string (car tail))) 1)
           (char=? (string-ref (symbol->string (car tail)) 0) #\:))
      (unless (init-name? (string->symbol (substring (symbol->string (car tail)) 1
                                                      (string-length (symbol->string (car tail))))))
        (error "invalid init category" (car tail) source-path))
      (parse (cdr tail) mode-value root-value
             (string->symbol (substring (symbol->string (car tail)) 1
                                        (string-length (symbol->string (car tail)))))
                rows options))
     (else
      (let (row (car tail))
        (unless (and (list? row) (pair? row) (init-name? (car row)))
          (error "expected a literal module row" row source-path))
        (let* ((id (string->symbol (if group (string-append (symbol->string group) "/" (symbol->string (car row)))
                                (symbol->string (car row)))))
               (disabled-value #f)
               (disable-specified-value #f)
               (source-root-value #f)
               (flags
                (let flags-loop ((rest (cdr row)) (result '()) (disable-seen? #f))
                  (cond
                   ((null? rest) (reverse result))
                   ((eq? (car rest) '@)
                    (unless (and (not source-root-value) (pair? (cdr rest))
                                 (string? (cadr rest)) (> (string-length (cadr rest)) 0))
                      (error "module @ requires one literal source directory" row source-path))
                    (set! source-root-value (cadr rest))
                    (flags-loop (cddr rest) result disable-seen?))
                   ((eq? (car rest) 'disable:)
                    (unless (and (not disable-seen?) (pair? (cdr rest)) (boolean? (cadr rest)))
                      (error "disable requires one Scheme boolean" row source-path))
                    (set! disabled-value (cadr rest))
                    (set! disable-specified-value #t)
                    (flags-loop (cddr rest) result #t))
                   ((and (symbol? (car rest))
                         (> (string-length (symbol->string (car rest))) 1)
                         (memv (string-ref (symbol->string (car rest)) 0) '(#\+ #\-)))
                    (let* ((flag (car rest)) (text (symbol->string flag))
                           (opposite (string->symbol
                                      (string-append (if (char=? (string-ref text 0) #\+) "-" "+")
                                                     (substring text 1 (string-length text))))))
                      (unless (init-name? (string->symbol (substring text 1 (string-length text))))
                        (error "invalid init feature name" flag source-path))
                      (when (or (memq flag result) (memq opposite result))
                        (error "conflicting init feature decisions" row source-path))
                      (flags-loop (cdr rest) (cons flag result) disable-seen?)))
                   (else (error "unsupported init flag or computed source" row source-path))))))
          (when (hash-key? seen id) (error "duplicate init module decision" id source-path))
          (hash-put! seen id #t)
          (parse (cdr tail) mode-value root-value group
                 (cons [id group (car row) flags disabled-value
                        disable-specified-value source-root-value] rows)
                 options)))))))

;; Windows normalize into the existing selection intent. Mount names route
;; values; they never rewrite publication/requirement identities.
(def (parse-init-windows body source-path)
  (match body
    ([] '())
    ([':load-modules (? string? root) . tail]
     (let split ((rest tail) (clauses '()))
       (if (or (null? rest) (eq? (car rest) ':load-modules))
         (with ([mode directory mount profile explicit? decisions package]
                (parse-init-window (cons* 'source: root (reverse clauses)) source-path #t))
           (def name (or mount (string->symbol (path-strip-directory
                                  (path-strip-trailing-directory-separator (path-expand root))))))
           ;; The declared window is the boundary. Like source: in a single
           ;; window, a relative path may reach a separate package checkout.
           (unless (> (string-length root) 0)
             (error "invalid directory window source" root))
           (unless (and (init-name? name)
                        (not (memq name '(build-spec build-current! test-spec test-current! tests))))
             (error "invalid or reserved directory mount" name))
           (cons [mode directory name profile explicit? decisions package]
                 (parse-init-windows rest source-path)))
         (split (cdr rest) (cons (car rest) clauses)))))
    (_ (error "directory window requires a literal source path" source-path))))

(def (parse-module-init forms source-path)
  (def declarations (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms))
  (unless (= (length declarations) 1) (error "init.ss requires exactly one yuanxu! declaration" source-path))
  (unless (andmap (lambda (form) (and (list? form) (pair? form)
                                    (memq (car form) '(import export yuanxu!)))) forms)
    (error "init.ss contains non-declarative forms" source-path))
  (def body (cdar declarations))
  (if (or (null? body) (not (eq? (car body) ':load-modules)))
    (values (list (parse-init-window body source-path)) #f)
    (let ((windows (parse-init-windows body source-path))
          (names (make-hash-table)) (roots (make-hash-table)) (ids (make-hash-table-eq)))
      (for-each
        (lambda (window)
         (with ([_ directory name _ _ decisions package] window)
          (def key (string-downcase (symbol->string name)))
          (def root (cons package (path-strip-trailing-directory-separator
                      (path-expand directory
                        (if source-path (path-directory source-path) (current-directory))))))
          (when (hash-key? names key) (error "duplicate directory mount" name))
          (when (hash-key? roots root) (error "duplicate directory window source" root))
          (hash-put! names key #t)
          (hash-put! roots root #t)
          ;; parse-init-window already rejects repeated names within a root.
          ;; Distinct roots are routed by native owner identity at discovery.
          )) windows)
      (values windows #t))))

(def (module-init-mounts forms)
  (let-values (((windows mounted?) (parse-module-init forms #f)))
    (if mounted?
      (map (lambda (window) (with ([_ _ mount _ _ _ _] window) mount)) windows)
      '(#f))))
