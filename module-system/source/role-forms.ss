;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core
;;; Gerbil-only role discovery shared by publication preparation and expansion.
(export yuanxu-module-allowed-entrypoint-roles yuanxu-module-required-role-files
        module-role-file module-publication-role-imports
        module-regular-role-file? module-init-export-name module-interface-form?
        module-feature-interface? module-feature-declaration?
        module-build-role-kind module-build-declaration?)

(def (module-build-declaration? form)
  (match form
    (['.def 'Build . _] #t)
    (['.def ['Build '@ _ . _] . _] #t)
    (else #f)))

(def (module-build-role-kind forms)
  (cond
    ((ormap (lambda (form) (and (pair? form) (eq? (car form) 'defbuild-script))) forms)
     'package-script)
    ((= 1 (length (filter module-build-declaration? forms))) 'make-parameters)
    (else 'invalid)))

(def (module-feature-declaration? path form)
  (and (string? path) (pair? form) (eq? (car form) '.def)
       (pair? (cdr form)) (eq? (cadr form) 'Feature)
       (string=? (path-strip-directory path) "interface.ss")
       (string=? (path-strip-directory
                    (path-strip-trailing-directory-separator
                      (path-directory (path-strip-trailing-directory-separator
                                        (path-directory path)))))
                 "features")))

(def (module-feature-interface? path forms)
  (and (list? forms)
       (andmap (lambda (form)
                 (and (pair? form) (list? form)
                      (or (eq? (car form) 'import)
                          (equal? form '(export Feature))
                          (module-feature-declaration? path form))))
               forms)
       (= 1 (length (filter (cut module-feature-declaration? path <>) forms)))))

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
  (def (publication-binding? name)
    (and (symbol? name)
         (ormap (lambda (source)
                  (and (pair? source) (eq? (car source) '.def) (pair? (cdr source))
                       (let (binding (cadr source))
                         (eq? (if (pair? binding) (car binding) binding) name))))
                forms)))
  (and (pair? form) (list? form)
       (case (car form)
         ((import .def) #t)
         ((export)
          (and (pair? (cdr form))
               (andmap
                 (lambda (spec)
                   (or (publication-binding? spec)
                       (and (list? spec) (pair? spec) (eq? (car spec) 'import:)
                            (pair? (cdr spec)) (andmap imported-file? (cdr spec)))))
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
  (map module-role-file '(types objects interface)))
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
(export init-name? parse-module-init module-init-windows module-init-build-roots)

(def (init-name? name)
  (and (symbol? name)
       (let (text (symbol->string name))
         (and (> (string-length text) 0) (not (member text '("." "..")))
              (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list text))))))
(def (test-directory-value directory source-path)
  (unless (string? directory) (error "test directory requires a literal path" source-path))
  (def relative (if (string-prefix? "./" directory)
                  (substring directory 2 (string-length directory)) directory))
  (unless (and (not (string-empty? relative))
               (andmap (lambda (part) (init-name? (string->symbol part)))
                       (string-split relative #\/)))
    (error "test directory must be relative to the yuanxu! declaration" directory source-path))
  relative)

(def (parse-init-window body source-path (root #f))
  (def window? (and root #t))
  (def mount-value #f)
  (def profile-value #f)
  (def test-dir "t")
  (def source-export #f)
  (def seen (make-hash-table-eq))
  (let parse ((tail body) (mode-value 'explicit) (root-value (or root "modules"))
              (group #f) (rows '()) (options '()))
    (cond
     ((null? tail)
      (unless (memq 'mode: options)
        (error "init.ss requires mode: explicit or mode: auto" source-path))
      (when (and (eq? mode-value 'explicit) (null? rows))
        (error "mode: explicit requires at least one Module leaf" source-path root-value))
      (when profile-value
        (unless (and (eq? mode-value 'auto) (or window? (memq 'source: options)))
          (error "profile selection requires source and auto mode" source-path)))
      [mode-value root-value mount-value profile-value
       (or window? (and (memq 'source: options) #t)) (reverse rows) test-dir source-export])
     ((not (pair? tail)) (error "improper init declaration" source-path))
     ((memq (car tail) '(mode: source: mount: profile: :test-dir export:))
      (let (key (car tail))
        (unless (and (pair? (cdr tail)) (not group) (null? rows) (not (memq key options)))
          (error "duplicate or misplaced init option" key source-path))
        (def value (cadr tail))
        (case key
          ((:test-dir) (set! test-dir (test-directory-value value source-path)))
          ((export:)
           (unless (and window? (init-name? value))
             (error "export: requires a ModuleSource binding name in a directory window" value))
           (set! source-export value))
          ((mode:) (unless (memq value '(auto explicit)) (error "invalid init mode" value)))
          ((source:)
           (unless (and (not window?) (string? value) (not (string-empty? value)))
             (error "invalid or duplicate init source" value)))
          ((profile:)
           (unless (init-name? value) (error "profile: requires a literal name" value))
           (set! profile-value value))
          ((mount:)
           (unless (and window? (or (string? value) (symbol? value)))
             (error "mount: requires a literal directory window name" value))
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
          (when (and (eq? mode-value 'auto) (not source-root-value)
                     (not disabled-value) (null? flags))
            (error "auto Loader discovers modules; omit the redundant module row" id source-path))
          (hash-put! seen id #t)
          (parse (cdr tail) mode-value root-value group
                 (cons [id group (car row) flags disabled-value
                        disable-specified-value source-root-value] rows)
                 options)))))))

;; Windows normalize into the existing selection intent. Mount names route
;; values; they never rewrite publication/requirement identities.
(def (init-source-reference? value)
  (match value
    (['from: (? symbol? owner) (? init-name? binding)]
     (let (name (symbol->string owner))
       (and (string-prefix? ":" name)
            (andmap (lambda (part) (and (not (string-empty? part))
                                        (init-name? (string->symbol part))))
                    (string-split (substring name 1 (string-length name)) #\/)))))
    (else #f)))

(def (parse-init-windows body source-path)
  (match body
    ([] '())
    ([':load-modules root . tail]
     (unless (or (and (string? root) (not (string-empty? root)))
                 (init-source-reference? root))
       (error "directory window requires a path or a public ModuleSource reference" root))
     (let split ((rest tail) (clauses '()))
       (if (or (null? rest) (eq? (car rest) ':load-modules))
         (with ([mode directory mount profile explicit? decisions test-dir binding]
                (parse-init-window (reverse clauses) source-path root))
           (def name
             (or mount
                 (if (string? root)
                   (string->symbol
                     (path-strip-directory (path-strip-trailing-directory-separator
                       (path-expand root
                         (if source-path (path-directory source-path) (current-directory))))))
                   (caddr root))))
           (unless (and (init-name? name)
                        (not (memq name '(build-spec build-current! test-spec test-current! tests))))
             (error "invalid or reserved directory mount" name))
           (when (and binding (not (string? root)))
             (error "only an owner path can export a ModuleSource" root binding))
           (when (and (not (string? root))
                      (ormap (lambda (row) (with ([_ _ _ _ _ _ override] row) override))
                             decisions))
             (error "ModuleSource window cannot change the package source of a module" root))
           (cons [mode directory name profile explicit? decisions test-dir binding]
                 (parse-init-windows rest source-path)))
         (split (cdr rest) (cons (car rest) clauses)))))
    (_ (error "expected a :load-modules window" source-path))))

(def (module-init-build-roots declaration)
  (let (body (cdr declaration))
    (if (and (pair? body) (eq? (car body) ':build-roots))
      (begin
        (unless (and (pair? (cdr body)) (list? (cadr body)) (andmap string? (cadr body)))
          (error ":build-roots requires a literal list of package-relative library names"))
        (cadr body))
      '())))

(def (parse-module-init forms source-path)
  ;; A native Gerbil header lets init import before the package prelude
  ;; exists. The source reader interprets only the inert declaration below.
  (when (and (pair? forms) (eq? (car forms) prelude:)
             (pair? (cdr forms)) (eq? (cadr forms) ':gerbil/core))
    (set! forms (cddr forms)))
  (def declarations (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms))
  (unless (= (length declarations) 1) (error "init.ss requires exactly one yuanxu! declaration" source-path))
  (unless (andmap (lambda (form) (and (list? form) (pair? form)
                                    (memq (car form) '(import export yuanxu!)))) forms)
    (error "init.ss contains non-declarative forms" source-path))
  (def declaration (car declarations))
  (def body (cdr declaration))
  (when (and (pair? body) (eq? (car body) ':build-roots))
    (module-init-build-roots declaration)
    (set! body (cddr body)))
  (if (or (null? body) (not (eq? (car body) ':load-modules)))
    (begin
      (when (memq ':load-modules body)
        (error "options belong inside a :load-modules window" source-path))
      (values (list (parse-init-window body source-path)) #f))
    (let ((windows (parse-init-windows body source-path))
          (names (make-hash-table)) (roots (make-hash-table))
          (bindings (make-hash-table-eq)))
      (for-each
        (lambda (window)
          (with ([_ directory name _ _ _ _ binding] window)
            (def key (string-downcase (symbol->string name)))
            (def root
              (if (string? directory)
                (path-strip-trailing-directory-separator
                  (path-expand directory
                    (if source-path (path-directory source-path) (current-directory))))
                directory))
            (when (hash-key? names key) (error "duplicate directory mount" name))
            (when (hash-key? roots root) (error "duplicate directory window source" root))
            (when binding
              (when (hash-key? bindings binding) (error "duplicate ModuleSource export" binding))
              (hash-put! bindings binding #t))
            (hash-put! names key #t)
            (hash-put! roots root #t))) windows)
      (for-each
        (lambda (binding)
          (when (or (memq binding '(tests std-make-spec admit-current))
                    (hash-key? names (string-downcase (symbol->string binding))))
            (error "ModuleSource export conflicts with an init binding" binding)))
        (hash-keys bindings))
      (values windows #t))))

(def (module-init-windows forms (source-path #f))
  (let-values (((windows mounted?) (parse-module-init forms source-path)))
    (if mounted?
      (map (lambda (window) (with ([_ _ mount _ _ _ _ binding] window) (cons mount binding))) windows)
      '())))
