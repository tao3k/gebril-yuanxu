;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Make output inventory/completion only; no publication or signing authority.
(import (only-in :std/string/path path-force-extension)
        (only-in "./program-products.ss" program-path program-identity?)
        (only-in :std/os/flock open-output-file/lock)
        (only-in :std/os/device device-close)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-type module-source-measure-operation))
(export artifact-files require-build-products! build-output-directory
        call-with-selected-output-lock selected-output-source-directory
        current-build-output-directory current-build-source-directory current-build-compiler-options current-build-module-roots static-product-path)

;; The output directory is an invocation parameter, not an approval.
(def current-build-output-directory (make-parameter #f))
(def current-build-source-directory (make-parameter #f))
(def current-build-compiler-options (make-parameter '()))
;; Only the current build invocation can narrow the init owner roots.
(def current-build-module-roots (make-parameter #f))

;; Gerbil's public Make entry accepts #f for its default. Only callers
;; inspecting output files need the concrete directory used by Make.
(def (build-output-directory (libdir (current-build-output-directory)))
  (or libdir (path-expand "lib" (gerbil-path))))

(def (call-with-selected-output-lock libdir action)
  (when (and (module-source-type libdir) (not (eq? (module-source-type libdir) 'directory)))
    (error "selected output environment is not a directory" libdir))
  (create-directory* libdir)
  (def path (path-expand ".yuanxu-source.lock" libdir))
  (when (and (module-source-type path) (not (eq? (module-source-type path) 'regular)))
    (error "selected compiler lock is not a regular file" path))
  (def lock
    (module-source-measure-operation 'build-output-lock
      (lambda () (open-output-file/lock path 120))))
  (dynamic-wind void action (lambda () (device-close lock))))

(def (selected-output-source-directory libdir)
  (def directory (path-expand ".yuanxu-source" libdir))
  (def kind (module-source-type directory))
  (when (and kind (not (eq? kind 'directory)))
    (error "selected source view is not a regular directory" directory))
  (when (module-source-type (path-expand "gerbil.pkg" directory))
    (error "selected source view must not supply a Make prefix" directory))
  (path-normalize directory))

(def (numeric? text)
  (and (not (string-empty? text)) (andmap char-numeric? (string->list text))))
(def (static-product-path identity libdir)
  (path-expand
    (path-force-extension
      (string-append "static/" (string-join (string-split (symbol->string identity) #\/) "__")) ".scm")
    libdir))

(def (missing-build-products identities libdir)
  (def markers (map (cut static-product-path <> libdir) identities))
  (def files (artifact-files identities libdir #f))
  (def (regular? path)
    (let (type (module-source-type path))
      (when (and type (not (eq? type 'regular)))
        (error "build product is non-regular or a symlink" path))
      (eq? type 'regular)))
  (append
    (filter (lambda (file) (not (regular? file)))
      (foldr append '()
        (map (lambda (id)
               (let (base (path-expand (symbol->string id) libdir))
                 (list (string-append base ".ssi") (string-append base ".o1")))) identities)))
    (filter (lambda (file) (not (regular? file)))
      (map (cut path-force-extension <> ".o1")
        (filter (lambda (file)
                  (and (string-suffix? ".scm" file) (not (member file markers)))) files)))))
(def (require-build-products! identities libdir)
  (let (missing (missing-build-products identities libdir))
    (unless (null? missing)
      (error "build-required: selected runtime products are incomplete" missing))))
(def (output-stem file)
  (let (suffix (find (cut string-suffix? <> file) '(".gxc-complete" ".ssxi.ss" ".ssi" ".scm" ".c")))
    (if suffix (substring file 0 (- (string-length file) (string-length suffix)))
      (let (dot (string-rindex file #\.))
        (and dot (string-prefix? ".o" (substring file dot (string-length file)))
             (numeric? (substring file (+ dot 2) (string-length file)))
             (substring file 0 dot))))))
(def (selected-stem? stem names)
  (and stem
    (or (hash-key? names stem)
        (let (separator (string-rindex stem #\~))
          (and separator (selected-stem? (substring stem 0 separator) names))))))
(def (artifact-files identities libdir (complete? #t) (programs '()))
  ;; Index selected names, then visit each selected directory ONCE per check.
  ;; Runtime named runtime sections (name~Type~0) belong to that selected unit.
  (def directories (make-hash-table))
  (for-each (lambda (identity)
    (def base (path-expand (symbol->string identity) libdir))
    (def directory (path-directory base))
    (when (and complete? (not (program-identity? identity programs))
               (not (and (file-exists? (string-append base ".ssi"))
                         (file-exists? (string-append base ".o1")))))
      (error "build-required: selected compiler output is missing" identity))
    (unless (hash-key? directories directory)
      (hash-put! directories directory (make-hash-table)))
    (hash-put! (hash-ref directories directory) (path-strip-directory base) #t))
    identities)
  (def files '())
  (hash-for-each (lambda (directory names)
    (for-each (lambda (file)
      (when (selected-stem? (output-stem file) names)
        (set! files (cons (path-expand file directory) files))))
      (if (file-exists? directory) (directory-files directory) '()))) directories)
  ;; Installed std/make's gxc-outputs requires BOTH .ssi and a static .scm.
  ;; A fresh publication must not depend on leftovers from an earlier raw build.
  ;; Inspect exact selected paths only; do not traverse the static catalogue.
  (def static-owners (make-hash-table))
  (for-each
    (lambda (identity)
      (def path (static-product-path identity libdir))
      (when (and (hash-key? static-owners path)
                 (not (eq? (hash-ref static-owners path) identity)))
        (error "selected compiler identities share a static output" identity))
      (hash-put! static-owners path identity)
      (let (type (module-source-type path))
        (when (or type (and complete? (not (program-identity? identity programs))))
          (unless (eq? type 'regular)
            (error "build-required: selected compiler static output is missing" identity))
          (set! files (cons path files))))) identities)
  (for-each
    (lambda (program)
      (def path (program-path program libdir))
      (def type (module-source-type path))
      (when (or type complete?)
        (unless (and (eq? type 'regular)
                     (not (zero? (bitwise-and (file-info-mode (file-info path #f)) #o111))))
          (error "build-required: selected program is missing or not executable" path))
        (set! files (cons path files)))) programs)
  (list-sort string<? files))
