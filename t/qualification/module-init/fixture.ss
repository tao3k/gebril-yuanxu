;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Test-only import of a freshly generated package through its real identity.
(import :clan/poo/object
        (only-in :std/list/list append-map)
        (only-in :std/misc/ports read-all-as-u8vector)
        (only-in :gerbil/expander core-read-module/sexp eval-syntax import-module
                 current-expander-context make-top-context)
        (only-in :yuanxu/observability/testing-fixture call-with-yuanxu-fixture)
        (only-in :yuanxu/ops/process-script ProcessScript.)
        (only-in :yuanxu/ops/func run-script)
        (only-in :yuanxu/observability/testing-script make-compiler-progress-reader)
        (only-in :yuanxu/module-system/source/role-forms module-init-export-name))
(export import-fixture-init! prepared-package-fixture call-with-prepared-package prepared-package-tests
        build-prepared-package!)
(def (import-fixture-init! path (fresh? #f))
  ;; A fresh top context has no import transformers until its prelude is bound.
  (eval-syntax '(import :gerbil/core))
  ;; Static Gerbil packages keep a stable compiler identity across Cases. Ask the
  ;; Gerbil for a new source context at this explicit Fixture boundary, rather
  ;; than sharing the previous Case's realized init object or weakening guards.
  (when fresh? (import-module path #t #t))
  (let-values (((_prelude identity _namespace _body) (core-read-module/sexp path)))
    (let (binding (module-init-export-name identity))
      (eval-syntax
        `(import (rename-in (only-in ,path ,binding) (,binding FixtureExports))))
      (eval-syntax 'FixtureExports))))

;; The Just build phase prepares these versioned Gerbil packages. Scheme owns
;; only reversible fault injection and admission; it never invokes a Builder.
(def (package-files root-value)
  (append-map
    (lambda (name)
      (def path (path-expand name root-value))
      (case (file-info-type (file-info path #f))
        ((regular) (list path))
        ((directory) (package-files path))
        (else (error "prepared package fixture must contain ordinary files" path))))
    (filter (lambda (name) (not (member name '("." ".."))))
      (directory-files root-value))))
(def (prepared-package-fixture root-value)
  (.o .acquire:
      (lambda ()
        ;; Capture before handing control to the Case. A lazy object slot must
        ;; never defer this resource snapshot until after fault injection.
        (def original-values
          (map (lambda (path) (cons path (call-with-input-file path read-all-as-u8vector)))
            (package-files root-value)))
        (.o root: root-value originals: original-values))
      .release:
      (lambda (workspace)
        (def originals (.get workspace originals))
        (for-each (lambda (path) (unless (assoc path originals) (delete-file path)))
          (package-files root-value))
        (for-each
          (lambda (row)
            (call-with-output-file (list path: (car row) truncate: #t)
              (lambda (out) (write-subu8vector (cdr row) 0 (u8vector-length (cdr row)) out))))
          originals))))
(def (call-with-prepared-package root-value action)
  (call-with-yuanxu-fixture (prepared-package-fixture root-value)
    (lambda (workspace) (action (.get workspace root)))))
(def (prepared-package-tests root-value)
  ;; Parent-side declaration discovery also needs the package's source lookup;
  ;; the actual child execution receives its admitted native publication first.
  (add-load-path! root-value)
  (parameterize ((current-expander-context (make-top-context)))
    (.get (import-fixture-init! (path-expand "init.ss" root-value) #t) tests)))

;; Explicitly authorized compiler qualification only. Ordinary preparation is
;; the Just Gerbil build phase. This effect proves a real injected compiler error;
;; it neither generates a runner nor replaces the Gerbil's build/test dispatcher.
(def (build-prepared-package! root-value options)
  (def inherited (getenv "GAMBOPT" ""))
  (run-script
    (.cc ProcessScript. 'directory root-value 'timeout 120 'idle-timeout 60
      'progress make-compiler-progress-reader
      'command (append '("gerbil") options '("build"))
      'environment
      (.o GAMBOPT:
        (string-join
          (append (if (zero? (string-length inherited)) '() (list inherited))
            (map (lambda (option)
                   (unless (string-prefix? "-:" option)
                     (error "fixture requires native Gambit runtime options" option))
                   (substring option 2 (string-length option))) options)) ",")))))
