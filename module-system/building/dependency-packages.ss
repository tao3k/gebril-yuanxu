;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Two-stage cross-package on-demand prerequisite compiler.
;;; Stage 1 discovers external package imports via Gerbil's native module reader
;;; (core-read-module/sexp), grouping missing or stale targets by dependency
;;; package root in topological order without evaluating module bodies or
;;; constructing business scopes.
;;; Stage 2 invokes native :std/make independently per dependency package with
;;; that package's own srcdir/gerbil.pkg inside call-with-build-input-path,
;;; keeping the consuming package's std-make-spec and clean single-package pure.
(import (only-in :gerbil/expander
                 core-read-module/sexp core-library-package-plist
                 core-import-module current-expander-module-import
                 current-expander-context make-top-context
                 syntax->datum)
        (only-in :gerbil/runtime/loader load-path)
        (only-in :std/list/list delete-duplicates/hash filter-map)
        (only-in :std/make make)
        (only-in :std/string/path path-default-extension)
        (only-in :tao3k/yuanxu/module-system/building/source-package
                 call-with-build-input-path call-with-build-source-fallbacks
                 package-library-prefix package-prelude-identity)
        (only-in :tao3k/yuanxu/module-system/building/products
                 build-output-directory call-with-selected-output-lock)
        (only-in :tao3k/yuanxu/module-system/source/role-forms
                 parse-module-init module-init-build-roots
                 yuanxu-module-allowed-entrypoint-roles))
(export ensure-dependency-packages-compiled!
        discover-dependency-packages
        plan-dependency-package-builds)

(def (canonical-dir path)
  (path-strip-trailing-directory-separator (path-normalize (path-expand path))))

(def (regular-file? path)
  (with-catch
    (lambda (_) #f)
    (lambda ()
      (eq? (file-info-type (file-info path #t)) 'regular))))

(def (directory-exists-follow? path)
  (with-catch
    (lambda (_) #f)
    (lambda ()
      (eq? (file-info-type (file-info path #t)) 'directory))))

(def (file-mtime-seconds path)
  (with-catch
    (lambda (_) #f)
    (lambda ()
      (time->seconds (file-info-last-modification-time (file-info path #t))))))

(def (strip-package-tag spec)
  (def text
    (cond
     ((string? spec) spec)
     ((symbol? spec) (symbol->string spec))
     (else #f)))
  (and text
       (let (at (string-index text #\@))
         (if at (substring text 0 at) text))))

(def (package-store-roots output-libdir)
  (def candidates
    (filter-map
      (lambda (dir)
        (and (string? dir) (directory-exists-follow? dir) (canonical-dir dir)))
      (list
        (and (string? output-libdir)
             (let (parent (path-directory (path-strip-trailing-directory-separator output-libdir)))
               (and (not (string-empty? parent)) (path-expand "pkg" parent))))
        (path-expand "pkg" (gerbil-path)))))
  (delete-duplicates/hash candidates key: identity))

(def (package-depend-specs directory)
  (let (plist (with-catch (lambda (_) '())
                (lambda () (core-library-package-plist directory #t))))
    (let (deps (and (list? plist) (pgetq depend: plist #f)))
      (if (list? deps) deps '()))))

;; Walk gerbil.pkg depend: entries transitively under active pkg/ stores.
;; Returns a list of package descriptors:
;;   #(root prefix prelude-identity)
;; sorted by longest prefix first for unambiguous longest-prefix matching.
(def (discover-dependency-packages root (output-libdir (build-output-directory)))
  (def self-root (canonical-dir root))
  (def stores (package-store-roots output-libdir))
  (def visited (make-hash-table))
  (def packages '())
  (hash-put! visited self-root #t)
  (def (find-dep-root dep-name)
    (let loop ((rest stores))
      (and (pair? rest)
           (let (candidate (path-expand dep-name (car rest)))
             (if (and (directory-exists-follow? candidate)
                      (regular-file? (path-expand "gerbil.pkg" candidate)))
               (canonical-dir candidate)
               (loop (cdr rest)))))))
  (def (walk-depends! dir)
    (for-each
      (lambda (spec)
        (let* ((dep-name (strip-package-tag spec))
               (dep-root (and dep-name (find-dep-root dep-name))))
          (when (and dep-root (not (hash-key? visited dep-root)))
            (hash-put! visited dep-root #t)
            (let ((prefix (package-library-prefix dep-root))
                  (prelude-id (with-catch (lambda (_) #f)
                                (lambda () (package-prelude-identity dep-root)))))
              (when (or prefix prelude-id)
                (set! packages (cons (vector dep-root (or prefix "") prelude-id) packages)))
              (walk-depends! dep-root)))))
      (package-depend-specs dir)))
  (unless (null? stores)
    (walk-depends! self-root))
  (list-sort
    (lambda (a b) (> (string-length (vector-ref a 1)) (string-length (vector-ref b 1))))
    packages))

(def (dep-pkg-root pkg) (vector-ref pkg 0))
(def (dep-pkg-prefix pkg) (vector-ref pkg 1))
(def (dep-pkg-prelude pkg) (vector-ref pkg 2))

(def (match-dependency-package dep-packages identity-str)
  (def identity-sym (string->symbol identity-str))
  (let loop ((rest dep-packages))
    (if (null? rest)
      (values #f #f)
      (let* ((pkg (car rest))
             (prefix (dep-pkg-prefix pkg))
             (prelude-id (dep-pkg-prelude pkg)))
        (cond
         ((and prelude-id (eq? identity-sym prelude-id))
          (values pkg "prelude"))
         ((and (not (string-empty? prefix)) (string-prefix? prefix identity-str))
          (values pkg (substring identity-str (string-length prefix) (string-length identity-str))))
         (else (loop (cdr rest))))))))

(def (collect-import-specs-from-spec spec base-dir libs files)
  (cond
   ((symbol? spec)
    (let (text (symbol->string spec))
      (when (and (> (string-length text) 1) (char=? (string-ref text 0) #\:))
        (libs (substring text 1 (string-length text))))))
   ((string? spec)
    (let (resolved (path-default-extension (path-expand spec base-dir) ".ss"))
      (files (path-normalize resolved))))
   ((pair? spec)
    (let ((head (car spec))
          (tail (cdr spec)))
      (case head
        ((only-in except-in except-out rename-in prefix-in)
         (when (pair? tail)
           (collect-import-specs-from-spec (car tail) base-dir libs files)))
        ((for-syntax for-template runtime: spec-in)
         (for-each (cut collect-import-specs-from-spec <> base-dir libs files) tail))
        ((phi:)
         (when (pair? tail)
           (for-each (cut collect-import-specs-from-spec <> base-dir libs files) (cdr tail))))
        ((group-in)
         (when (and (pair? tail) (pair? (cdr tail)))
           (let ((prefix (car tail))
                 (subspecs (cdr tail)))
             (for-each
               (lambda (sub)
                 (cond
                  ((and (symbol? prefix) (symbol? sub))
                   (let ((ptext (symbol->string prefix))
                         (stext (symbol->string sub)))
                     (when (and (> (string-length ptext) 1) (char=? (string-ref ptext 0) #\:))
                       (libs (string-append (substring ptext 1 (string-length ptext)) "/" stext)))))
                  ((and (string? prefix) (or (string? sub) (symbol? sub)))
                   (let ((sub-str (if (symbol? sub) (symbol->string sub) sub)))
                     (files (path-normalize
                              (path-default-extension
                                (path-expand (string-append prefix "/" sub-str) base-dir) ".ss")))))))
               subspecs))))
        (else (void)))))))

(def (collect-imports-from-forms forms base-dir libs files)
  (for-each
    (lambda (form)
      (when (pair? form)
        (case (car form)
          ((import)
           (for-each (cut collect-import-specs-from-spec <> base-dir libs files) (cdr form)))
          ((begin begin-syntax begin-foreign)
           (collect-imports-from-forms (cdr form) base-dir libs files))
          ((module)
           (when (and (pair? (cdr form)) (pair? (cddr form)))
             (collect-imports-from-forms (cddr form) base-dir libs files)))
          ((cond-expand)
           (for-each
             (lambda (clause)
               (when (and (pair? clause) (pair? (cdr clause)))
                 (collect-imports-from-forms (cdr clause) base-dir libs files)))
             (cdr form)))
          ((include)
           (when (and (pair? (cdr form)) (string? (cadr form)))
             (let (inc-path (path-normalize (path-expand (cadr form) base-dir)))
               (when (regular-file? inc-path)
                 (let (inc-forms (with-catch (lambda (_) '())
                                   (lambda () (call-with-input-file inc-path read-all))))
                   (collect-imports-from-forms inc-forms (path-directory inc-path) libs files)))))))))
    forms))

;; Read a module via Gerbil's native module reader (core-read-module/sexp),
;; returning (values library-identity-strings relative-source-paths).
(def (read-module-import-edges path)
  (def libs '())
  (def files '())
  (def base-dir (path-directory path))
  (def (add-lib! id-str) (set! libs (cons id-str libs)))
  (def (add-file! f) (set! files (cons f files)))
  (with-catch
    (lambda (_) (void))
    (lambda ()
      (let-values (((prelude _id _ns body) (core-read-module/sexp path)))
        (let (p (and prelude (syntax->datum prelude)))
          (when (symbol? p)
            (let (text (symbol->string p))
              (when (and (> (string-length text) 1) (char=? (string-ref text 0) #\:))
                (add-lib! (substring text 1 (string-length text)))))))
        (let* ((datum (syntax->datum body))
               (forms (cond ((list? datum) datum)
                            ((pair? datum) (list datum))
                            (else '()))))
          (collect-imports-from-forms forms base-dir add-lib! add-file!)))))
  (values (reverse libs) (reverse files)))

;; Extract literal Build spec / ffi target filenames and autoload module
;; library identities from an adjacent build.ss purely as inert syntax data
;; (never evaluating Build).
(def (extract-build-role-seeds build-file)
  (def targets '())
  (def lib-ids '())
  (def (add-target! name)
    (when (and (string? name) (not (string-empty? name)))
      (set! targets (cons name targets))))
  (def (add-lib! sym)
    (when (symbol? sym)
      (let (text (symbol->string sym))
        (when (and (> (string-length text) 1) (char=? (string-ref text 0) #\:))
          (set! lib-ids (cons (substring text 1 (string-length text)) lib-ids))))))
  (def (collect-spec-datum datum)
    (cond
     ((string? datum) (add-target! datum))
     ((pair? datum)
      (if (and (memq (car datum) '(gxc: gsc: exe: ssi:))
               (pair? (cdr datum))
               (string? (cadr datum)))
        (add-target! (cadr datum))
        (for-each collect-spec-datum datum)))))
  (def (collect-spec-expr expr)
    (when (pair? expr)
      (case (car expr)
        ((quote quasiquote)
         (when (pair? (cdr expr))
           (collect-spec-datum (cadr expr))))
        ((list append cons)
         (for-each collect-spec-expr (cdr expr)))
        ((cond-expand)
         (for-each
           (lambda (clause)
             (when (and (pair? clause) (pair? (cdr clause)))
               (for-each collect-spec-expr (cdr clause))))
           (cdr expr)))
        (else
         (when (string? (car expr)) (add-target! (car expr)))
         (for-each collect-spec-expr expr)))))
  (def (walk form)
    (when (pair? form)
      (cond
       ((and (memq (car form) '(spec: ffi:)) (pair? (cdr form)))
        (collect-spec-expr (cadr form))
        (walk (cddr form)))
       ((and (eq? (car form) 'module:) (pair? (cdr form)))
        (let (val (cadr form))
          (cond
           ((symbol? val) (add-lib! val))
           ((and (pair? val) (eq? (car val) 'quote) (pair? (cdr val)))
            (add-lib! (cadr val)))))
        (walk (cddr form)))
       (else
        (walk (car form))
        (walk (cdr form))))))
  (when (regular-file? build-file)
    (with-catch (lambda (_) (void))
      (lambda ()
        (let-values (((_p _id _ns body) (core-read-module/sexp build-file)))
          (walk (syntax->datum body))))))
  (values (reverse targets) (reverse lib-ids)))

(def (discover-auto-module-dirs dir)
  (def found '())
  (def (walk current depth)
    (when (and (directory-exists-follow? current) (< depth 4))
      (if (regular-file? (path-expand "interface.ss" current))
        (set! found (cons (canonical-dir current) found))
        (for-each
          (lambda (name)
            (unless (or (string-prefix? "." name)
                        (member name '("t" "tests" "features" "node_modules")))
              (let (child (path-expand name current))
                (when (directory-exists-follow? child)
                  (walk child (+ depth 1))))))
          (with-catch (lambda (_) '()) (lambda () (directory-files current)))))))
  (walk dir 0)
  (reverse found))

(def (seed-module-dir-files! mod-dir enabled-features add-seed! add-lib-seed!)
  (for-each
    (lambda (role)
      (let (f (path-expand (string-append (symbol->string role) ".ss") mod-dir))
        (when (regular-file? f) (add-seed! f))))
    yuanxu-module-allowed-entrypoint-roles)
  ;; Also include plural funcs.ss if a module uses that naming convention.
  (let (funcs (path-expand "funcs.ss" mod-dir))
    (when (regular-file? funcs) (add-seed! funcs)))
  ;; Seed any build.ss declared targets (e.g. entry.ss, FFI leaves, autoload modules).
  (let-values (((targets libs) (extract-build-role-seeds (path-expand "build.ss" mod-dir))))
    (for-each
      (lambda (target)
        (let (f (path-normalize (path-default-extension (path-expand target mod-dir) ".ss")))
          (when (regular-file? f) (add-seed! f))))
      targets)
    (for-each add-lib-seed! libs))
  ;; Seed enabled feature interface.ss files.
  (for-each
    (lambda (feat)
      (let (f (path-expand (string-append "features/" feat "/interface.ss") mod-dir))
        (when (regular-file? f) (add-seed! f))))
    enabled-features))

(def (collect-seed-source-files root init-file declaration module-ids mount-names package-roots?)
  (def seeds '())
  (def lib-seeds '())
  (def seen (make-hash-table))
  (def lib-seen (make-hash-table))
  (def (add-seed! path)
    (let (norm (path-normalize path))
      (when (and (regular-file? norm) (not (hash-key? seen norm)))
        (hash-put! seen norm #t)
        (set! seeds (cons norm seeds)))))
  (def (add-lib-seed! id-str)
    (when (and (string? id-str) (not (hash-key? lib-seen id-str)))
      (hash-put! lib-seen id-str #t)
      (set! lib-seeds (cons id-str lib-seeds))))
  (add-seed! init-file)
  (when package-roots?
    (for-each
      (lambda (name)
        (add-seed! (path-default-extension (path-expand name root) ".ss")))
      (module-init-build-roots declaration)))
  (def init-dir (path-directory init-file))
  (def has-filter? (or (and (pair? module-ids) #t) (and (pair? mount-names) #t)))
  (def (module-selected? mount id)
    (or (not has-filter?)
        (and (pair? mount-names) (memq mount mount-names) #t)
        (and (pair? module-ids)
             (or (memq id module-ids)
                 (and mount
                      (memq (string->symbol
                              (string-append (symbol->string mount) "/" (symbol->string id)))
                            module-ids))))))
  (with-catch
    (lambda (_) (void))
    (lambda ()
      (let-values (((windows _mounted?) (parse-module-init (list declaration) init-file)))
        (for-each
          (lambda (window)
            (with ([mode directory mount _profile _explicit? decisions _test-dir _binding _gprof] window)
              (when (string? directory)
                (let ()
                  (def win-root (canonical-dir (path-expand directory init-dir)))
                  (def disabled (make-hash-table))
                  (def explicit-dirs '())
                  (for-each
                    (lambda (row)
                      (with ([id _group _name flags disabled? _dis-spec override-root _rprof] row)
                        (def mod-dir
                          (canonical-dir
                            (if override-root
                              (path-expand override-root init-dir)
                              (path-expand (symbol->string id) win-root))))
                        (if disabled?
                          (hash-put! disabled mod-dir #t)
                          (when (module-selected? mount id)
                            (let ((enabled-feats
                                   (filter-map
                                     (lambda (flag)
                                       (let (s (symbol->string flag))
                                         (and (> (string-length s) 1) (char=? (string-ref s 0) #\+)
                                              (substring s 1 (string-length s)))))
                                     flags)))
                              (set! explicit-dirs (cons (cons mod-dir enabled-feats) explicit-dirs)))))))
                    decisions)
                  (for-each
                    (lambda (entry)
                      (seed-module-dir-files! (car entry) (cdr entry) add-seed! add-lib-seed!))
                    (reverse explicit-dirs))
                  (when (and (eq? mode 'auto)
                             (or (not has-filter?)
                                 (and (pair? mount-names) (memq mount mount-names))
                                 (pair? module-ids)))
                    (for-each
                      (lambda (mod-dir)
                        (unless (hash-key? disabled mod-dir)
                          (let* ((rel-id
                                  (let (prefix (string-append win-root "/"))
                                    (and (string-prefix? prefix mod-dir)
                                         (string->symbol (substring mod-dir (string-length prefix)
                                                                    (string-length mod-dir)))))))
                            (when (or (not has-filter?)
                                      (and (pair? mount-names) (memq mount mount-names))
                                      (and rel-id (module-selected? mount rel-id)))
                              (seed-module-dir-files! mod-dir '() add-seed! add-lib-seed!)))))
                      (discover-auto-module-dirs win-root)))))))
          windows))))
  (values (reverse seeds) (reverse lib-seeds)))

(def (existing-ssi-mtime compiler-id-str search-dirs)
  (def rel (string-append compiler-id-str ".ssi"))
  (let loop ((rest search-dirs))
    (and (pair? rest)
         (let (candidate (path-expand rel (car rest)))
           (if (regular-file? candidate)
             (file-mtime-seconds candidate)
             (loop (cdr rest)))))))

;; Stage 1: Pure discovery & staleness analysis.
;; Returns a topologically ordered list of (dep-root . stale-target-names) pairs
;; for external dependency packages that have missing or stale .ssi artifacts.
;; Returns '() when no dependency packages exist or all imported .ssi artifacts
;; are already present and fresh.
(def (plan-dependency-package-builds root init-file declaration
                                     (output-libdir (build-output-directory))
                                     module-ids: (module-ids #f)
                                     mount-names: (mount-names #f)
                                     package-roots?: (package-roots? #t))
  (def dep-packages (discover-dependency-packages root output-libdir))
  (if (null? dep-packages)
    '()
    (let ()
      (def self-root (canonical-dir root))
      (def self-root-prefix (string-append self-root "/"))
      (def self-prefix (or (package-library-prefix self-root) ""))
      (def self-prelude (with-catch (lambda (_) #f) (lambda () (package-prelude-identity self-root))))
      (def pkg-by-root (make-hash-table))
      (def pkg-mtime (make-hash-table))
      (for-each
        (lambda (pkg)
          (let (droot (dep-pkg-root pkg))
            (hash-put! pkg-by-root droot pkg)
            (hash-put! pkg-mtime droot
              (or (file-mtime-seconds (path-expand "gerbil.pkg" droot)) 0.0))))
        dep-packages)
      (def file-state (make-hash-table))      ;; norm-path -> 'visiting | max-mtime (flonum)
      (def dep-targets (make-hash-table))     ;; dep-root -> rev list of #(target source-path compiler-id)
      (def dep-target-seen (make-hash-table)) ;; (cons dep-root target) -> #t
      (def pkg-deps (make-hash-table))        ;; dep-root -> list of dep-roots it imports

      (def (record-pkg-edge! from-pkg to-pkg)
        (when (and from-pkg to-pkg (not (equal? (dep-pkg-root from-pkg) (dep-pkg-root to-pkg))))
          (let* ((from-root (dep-pkg-root from-pkg))
                 (to-root (dep-pkg-root to-pkg))
                 (existing (hash-ref pkg-deps from-root '())))
            (unless (member to-root existing)
              (hash-put! pkg-deps from-root (cons to-root existing))))))

      (def (owner-dep-package norm-path)
        (let loop ((rest dep-packages))
          (and (pair? rest)
               (let* ((pkg (car rest))
                      (droot-prefix (string-append (dep-pkg-root pkg) "/")))
                 (if (string-prefix? droot-prefix norm-path)
                   pkg
                   (loop (cdr rest)))))))

      (def (record-dep-target! pkg target norm-path)
        (def droot (dep-pkg-root pkg))
        (def key (string-append droot ":" target))
        (unless (hash-key? dep-target-seen key)
          (hash-put! dep-target-seen key #t)
          (let* ((prelude-id (dep-pkg-prelude pkg))
                 (compiler-id
                  (if (and prelude-id (string=? target "prelude"))
                    (symbol->string prelude-id)
                    (string-append (dep-pkg-prefix pkg) target))))
            (hash-put! dep-targets droot
              (cons (vector target norm-path compiler-id)
                    (hash-ref dep-targets droot '()))))))

      (def (visit-file! norm-path current-pkg)
        (let (state (hash-get file-state norm-path))
          (cond
           ((number? state) state)
           ((eq? state 'visiting) 0.0)
           ((not (regular-file? norm-path)) 0.0)
           (else
            (hash-put! file-state norm-path 'visiting)
            (let* ((own-mtime (or (file-mtime-seconds norm-path) 0.0))
                   (base-mtime
                    (if current-pkg
                      (max own-mtime (hash-ref pkg-mtime (dep-pkg-root current-pkg) 0.0))
                      own-mtime))
                   (max-mtime base-mtime))
              (let-values (((libs files) (read-module-import-edges norm-path)))
                (for-each
                  (lambda (lib-id)
                    (let-values (((target-pkg target-rel)
                                  (match-dependency-package dep-packages lib-id)))
                      (cond
                       (target-pkg
                        (record-pkg-edge! current-pkg target-pkg)
                        (let (target-path
                              (path-normalize
                                (path-expand (string-append target-rel ".ss") (dep-pkg-root target-pkg))))
                          (when (regular-file? target-path)
                            (let (dep-mtime (visit-file! target-path target-pkg))
                              (set! max-mtime (max max-mtime dep-mtime))
                              (record-dep-target! target-pkg target-rel target-path)))))
                       ((and (not current-pkg)
                             (or (and self-prelude (eq? (string->symbol lib-id) self-prelude))
                                 (and (not (string-empty? self-prefix))
                                      (string-prefix? self-prefix lib-id))))
                        (let* ((local-rel
                                (if (and self-prelude (eq? (string->symbol lib-id) self-prelude))
                                  "prelude"
                                  (substring lib-id (string-length self-prefix) (string-length lib-id))))
                               (local-path
                                (path-normalize
                                  (path-expand (string-append local-rel ".ss") self-root))))
                          (when (regular-file? local-path)
                            (let (dep-mtime (visit-file! local-path #f))
                              (set! max-mtime (max max-mtime dep-mtime)))))))))
                  libs)
                (for-each
                  (lambda (rel-path)
                    (cond
                     (current-pkg
                      (let (droot-prefix (string-append (dep-pkg-root current-pkg) "/"))
                        (when (and (string-prefix? droot-prefix rel-path)
                                   (regular-file? rel-path))
                          (let* ((rel-with-ext
                                  (substring rel-path (string-length droot-prefix) (string-length rel-path)))
                                 (rel-target (path-strip-extension rel-with-ext))
                                 (dep-mtime (visit-file! rel-path current-pkg)))
                            (set! max-mtime (max max-mtime dep-mtime))
                            (record-dep-target! current-pkg rel-target rel-path)))))
                     ((string-prefix? self-root-prefix rel-path)
                      (when (regular-file? rel-path)
                        (let (dep-mtime (visit-file! rel-path #f))
                          (set! max-mtime (max max-mtime dep-mtime)))))
                     (else
                      (let (ext-pkg (owner-dep-package rel-path))
                        (when (and ext-pkg (regular-file? rel-path))
                          (let* ((droot-prefix (string-append (dep-pkg-root ext-pkg) "/"))
                                 (rel-target
                                  (path-strip-extension
                                    (substring rel-path (string-length droot-prefix)
                                               (string-length rel-path))))
                                 (dep-mtime (visit-file! rel-path ext-pkg)))
                            (set! max-mtime (max max-mtime dep-mtime))
                            (record-dep-target! ext-pkg rel-target rel-path)))))))
                  files))
              (hash-put! file-state norm-path max-mtime)
              max-mtime)))))

      ;; Also seed root's gerbil.pkg prelude if it belongs to a dependency package.
      (let (plist (with-catch (lambda (_) '()) (lambda () (core-library-package-plist self-root #t))))
        (let (root-prelude (and (list? plist) (pgetq prelude: plist #f)))
          (when (symbol? root-prelude)
            (let (text (symbol->string root-prelude))
              (when (and (> (string-length text) 1) (char=? (string-ref text 0) #\:))
                (let-values (((target-pkg target-rel)
                              (match-dependency-package dep-packages
                                (substring text 1 (string-length text)))))
                  (when target-pkg
                    (let (target-path
                          (path-normalize
                            (path-expand (string-append target-rel ".ss") (dep-pkg-root target-pkg))))
                      (when (regular-file? target-path)
                        (visit-file! target-path target-pkg)
                        (record-dep-target! target-pkg target-rel target-path))))))))))

      ;; Walk all selected seed files and autoload library roots in the current package.
      ;; Supply dep-roots as read fallbacks so core-read-module/sexp can read
      ;; dependency modules that declare an uncompiled package-local prelude.
      (call-with-build-source-fallbacks (map dep-pkg-root dep-packages)
        (lambda ()
          (let-values (((seed-files seed-libs)
                        (collect-seed-source-files self-root init-file declaration
                          module-ids mount-names package-roots?)))
            (for-each
              (lambda (seed) (visit-file! seed #f))
              seed-files)
            (for-each
              (lambda (lib-id)
                (let-values (((target-pkg target-rel)
                              (match-dependency-package dep-packages lib-id)))
                  (cond
                   (target-pkg
                    (let (target-path
                          (path-normalize
                            (path-expand (string-append target-rel ".ss") (dep-pkg-root target-pkg))))
                      (when (regular-file? target-path)
                        (visit-file! target-path target-pkg)
                        (record-dep-target! target-pkg target-rel target-path))))
                   ((or (and self-prelude (eq? (string->symbol lib-id) self-prelude))
                        (and (not (string-empty? self-prefix))
                             (string-prefix? self-prefix lib-id)))
                    (let* ((local-rel
                            (if (and self-prelude (eq? (string->symbol lib-id) self-prelude))
                              "prelude"
                              (substring lib-id (string-length self-prefix) (string-length lib-id))))
                           (local-path
                            (path-normalize
                              (path-expand (string-append local-rel ".ss") self-root))))
                      (when (regular-file? local-path)
                        (visit-file! local-path #f)))))))
              seed-libs))))

      ;; Topological sort of dependency packages that have targets.
      (def active-roots (hash-keys dep-targets))
      (def topo-seen (make-hash-table))
      (def topo-order '())
      (def (topo-visit! droot)
        (unless (hash-key? topo-seen droot)
          (hash-put! topo-seen droot #t)
          (for-each
            (lambda (dep)
              (when (hash-key? dep-targets dep)
                (topo-visit! dep)))
            (hash-ref pkg-deps droot '()))
          (set! topo-order (cons droot topo-order))))
      (for-each topo-visit! (list-sort string<? active-roots))

      ;; Filter to only missing or stale targets per dependency package.
      (def search-dirs
        (delete-duplicates/hash
          (append (if (string? output-libdir) (list output-libdir) '())
                  (load-path))
          key: canonical-dir))
      (filter-map
        (lambda (droot)
          (let* ((ordered (reverse (hash-ref dep-targets droot '())))
                 (stale
                  (filter-map
                    (lambda (row)
                      (let* ((target (vector-ref row 0))
                             (src (vector-ref row 1))
                             (compiler-id (vector-ref row 2))
                             (src-mtime (hash-ref file-state src 0.0))
                             (ssi-mtime (existing-ssi-mtime compiler-id search-dirs)))
                        (and (or (not ssi-mtime) (> src-mtime ssi-mtime))
                             target)))
                    ordered)))
            (and (pair? stale) (cons droot stale))))
        (reverse topo-order)))))

;; Stage 2: Compile only missing or stale targets per dependency package,
;; using each dependency package's own srcdir/gerbil.pkg via native :std/make
;; strictly inside call-with-build-input-path and call-with-selected-output-lock.
(def (ensure-dependency-packages-compiled! root init-file declaration
                                           output-libdir refuse-input-context!
                                           (module-ids #f)
                                           (mount-names #f)
                                           (package-roots? #t)
                                           (compile-package #f))
  (def plan
    (plan-dependency-package-builds root init-file declaration output-libdir
      module-ids: module-ids mount-names: mount-names package-roots?: package-roots?))
  (unless (null? plan)
    (call-with-selected-output-lock output-libdir
      (lambda ()
        (for-each
          (lambda (entry)
            (def dep-root (car entry))
            (def stale-targets (cdr entry))
            (call-with-build-input-path output-libdir
              (lambda ()
                (call-with-build-input-path #f
                  (lambda ()
                    (parameterize ((current-expander-module-import core-import-module)
                                   (current-expander-context (make-top-context)))
                      (if compile-package
                        (compile-package stale-targets dep-root output-libdir)
                        (make stale-targets srcdir: dep-root libdir: output-libdir force: #t))))
                  refuse-input-context! make-source: dep-root))
              refuse-input-context!))
          plan))))
  plan)
