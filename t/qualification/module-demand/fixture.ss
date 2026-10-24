;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Isolated source projection. No production reader or Loader is changed.
(import :clan/poo/object
        (only-in ./projection-syntax include-projected-interface)
        (only-in :std/source this-source-file)
        (only-in :std/list/list-builder with-list-builder)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :gerbil/expander core-read-module/sexp syntax->datum)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture)
        (only-in :yuanxu/module-system/source/role-forms
                 module-publication-role-imports module-regular-role-file?)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-private-source)
        (only-in :yuanxu/module-system/source/reader module-prepared-source-binding)
        (only-in :yuanxu/module-system/source/admission
                 module-source-read module-source-admit-current!))
(export ProjectionFixture project-metadata load-role scope-context)
(def sources (path-expand "sources" (path-directory (this-source-file))))
(def (forms path)
  (let-values (((_prelude _id _namespace body) (core-read-module/sexp path)))
    (map syntax->datum body)))
(def (slot-rows body)
  ;; Closed keyword/value syntax only. No macro calls, inheritance options or
  ;; duplicate fields are admitted as structural metadata.
  (let loop ((rest body) (seen '()))
    (match rest
      ([] '())
      ([(? keyword? key) value . tail]
       (when (memq key seen) (error "duplicate metadata slot" key))
       (cons (cons key value) (loop tail (cons key seen))))
      (else (error "open slot syntax requires original guarded reader" rest)))))
(def (field rows key)
  (cond ((assq key rows) => cdr)
        (else (error "missing closed metadata field" key))))
(def (literal-symbol term)
  (match term (['quote (? symbol? id)] id)
    (else (error "calculated dependency needs the original guarded reader" term))))
(def (native-object-body term)
  (match term
    (['.o [':: (? symbol?) parents] . body]
     (unless (equal? parents (list '@list)) (error "inherited metadata requires original reader" parents))
     (slot-rows body))
    (['.o . body] (slot-rows body))
    (else (error "nonliteral native object requires original reader" term))))
(def (project-metadata path)
  ;; Classify the actual source shape, never a manually supplied purity bit.
  (match (forms path)
    ([['.def binding . body]]
     (unless (or (eq? binding 'Module)
                 (match binding
                   (['Module (? symbol?) parents] (equal? parents (list '@list)))
                   (else #f)))
       (error "inherited module metadata requires original guarded reader" binding))
     (def slots (slot-rows body))
     (def core (native-object-body (field slots 'core:)))
     (def requirements (native-object-body (field core 'requires:)))
     (unless (null? (native-object-body (field slots 'features:)))
       (error "feature-bearing metadata requires original guarded reader" path))
     (def id (literal-symbol (field slots 'identity:)))
     (def ids (map (lambda (row)
                     (literal-symbol (field (native-object-body (cdr row)) 'module-id:)))
                   requirements))
     (.o identity: id requires: ids))
    (else (error "open interface requires original guarded reader" path))))
(def (exports path)
  (with-list-builder (emit)
    (for-each (lambda (form)
      (match form
        (['export . names]
         (unless (andmap symbol? names) (error "nonliteral export needs original reader" path))
         (for-each emit names))
        (else (void)))) (forms path))))
(def (load-role root name names rows)
  (module-source-admit-current! rows "projected module source changed")
  (def owner (path-normalize root))
  (def prepared (yuanxu-prepare-module-private-source owner (path-expand name owner) void))
  (def binding (string->symbol (symbol->string (gensym 'RoleValues))))
  ;; Extend the SAME existing native include wrapper with an ordinary POO
  ;; tuple of actual exports. Never reconstruct or replace issued read tokens.
  (def bundled
    (.cc prepared compiler-forms:
      (append (.get prepared compiler-forms)
        (list '(import :clan/poo/object)
              `(def ,binding (.o ,@names))))))
  (def value (module-prepared-source-binding bundled binding))
  (module-source-admit-current! rows "projected module source changed")
  value)
(def (write-forms path body)
  (call-with-output-file path
    (lambda (port) (for-each (lambda (form) (write form port) (newline port)) body))))
(def (prepare-projection workspace)
  (def root (.get workspace root))
  (write-forms (path-expand "gerbil.pkg" root)
    `((package: ,(symbol->string (gensym 'demand-)) prelude: :gerbil/core)))
  (for-each (lambda (name) (copy-file (path-expand name sources) (path-expand name root)))
    '("types.ss" "objects.ss" "config.ss" "func.ss" "interface.ss"))
  (def interface (path-expand "interface.ss" root))
  (def metadata (project-metadata interface))
  ;; The existing role-layout operation, not a hand-maintained exports index.
  (def roles
    (map (lambda (relative)
           (def path (path-expand relative root))
           (list (string->symbol (path-strip-extension (path-strip-directory path)))
                 (path-strip-directory path) (exports path)))
      (module-publication-role-imports root module-regular-role-file?)))
  (def names (with-list-builder (emit)
               (for-each (lambda (role) (for-each emit (caddr role))) roles)))
  (unless (= (length names) (length (delete-duplicates/hash names)))
    (error "conflicting role exports" names))
  (def rows
    (map (lambda (name) (def path (path-expand name root)) (cons path (module-source-read path)))
      (append '("gerbil.pkg" "interface.ss") (map cadr roles))))
  (def wrapper (path-expand "projected.ss" root))
  (write-forms wrapper
    `((import (except-in :clan/poo/object .def)
              (only-in :yuanxu/module-system/source/declaration .def)
              (only-in :yuanxu/t/qualification/module-demand/projection-syntax include-projected-interface)
              (only-in :yuanxu/t/qualification/module-demand/fixture load-role))
      (def core 'outer-core-must-not-be-used)
      (def SourceRows ',rows)
      (def (make-role-bindings)
        (.o (:: role-self '())
          ,@(with-list-builder (emit)
              (for-each (lambda (role)
                (emit (string->keyword (symbol->string (car role))))
                (emit `(load-role ,root ,(cadr role) ',(caddr role) SourceRows))) roles))
          ,@(with-list-builder (emit)
              (for-each (lambda (role)
                (for-each (lambda (name)
                  (emit (string->keyword (symbol->string name)))
                  (emit `(.get role-self ,(car role) ,name))) (caddr role))) roles))))
      (include-projected-interface ,interface (,@names))))
  (.o root metadata sources: rows
      module:
      (module-prepared-source-binding
        (yuanxu-prepare-module-private-source (path-normalize root) (path-normalize wrapper) void) 'Module)))
(.def (ProjectionFixture @ DirectoryFixture)
  prefix: "core-module-demand-"
  .prepare: prepare-projection)
(def (scope-context module (a '(5432 5433)) (b '(5432 5433)))
  (.o effective-config: (.get module core config) allowed-a: a allowed-b: b))
