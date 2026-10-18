;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .get object?)
        (only-in :core/observability/testing-case poo-flow-test-case)
        (only-in :core/types poo-flow-predicate-contract poo-flow-validation-evidence-accepted?)
        :core/module-system/source/collection
        :core/module-system/source/objects
        :core/module-system/source/admission
        :core/module-system/interface)
(export module-source-admission-test)
(def ScopeContract
  (poo-flow-predicate-contract 'test/source-scope object? (lambda (_v _c) '())))
(def (write-role root role text)
  (let (path (path-expand (string-append "modules/custom/example/" role ".ss") root))
    (create-directory* (path-directory path))
    (call-with-output-file (list path: path truncate: #t) (lambda (port) (display text port)))))
(def (remove-source path)
  (if (eq? (module-source-type path) 'directory)
    (begin (for-each (lambda (name) (remove-source (path-expand name path))) (directory-files path))
           (delete-directory path))
    (delete-file path)))
(def (with-module test)
  (let (root (make-temporary-file-name "module-source-admission-"))
    (dynamic-wind
     (lambda ()
       (write-role root "types" "(def PublicContract 'contract)")
       (write-role root "objects" "(import \"types.ss\") (def Defaults 'default)")
       (write-role root "config" "(import \"objects.ss\") (def Config 'configured)")
       ;; Publish one object, without importing/re-exporting every private role.
       (write-role root "interface" "(import \"config.ss\") (.def Published identity: 'custom/example) (export Published)"))
     (lambda () (test root))
     (lambda () (remove-source root)))))
(def (publication)
  (.o identity: 'custom/example features: (.o)
      core: (.o requires: (.o) scope-contract: ScopeContract
                link: (lambda (_dependencies) (.o ready: #t)))))
(def (collection-source root)
  (let (collection (make-poo-flow-module-source-collection
                   'fixture 'test root "modules/custom"))
    (poo-flow-module-source-collection-locate collection '(custom . example))))
(def (directory-scope root reader)
  (.get (poo-flow-load-modules (path-expand "modules" root) read-publication: reader)
        modules custom example))
(def (both-refuse root)
  (let (reads 0)
    (check-exception (collection-source root) error?)
    (check-exception (directory-scope root (lambda (_source) (set! reads (+ reads 1)) (publication))) error?)
    (check-equal? reads 0)))
(def module-source-admission-test
  (test-suite "One source-role admission for directory and collection"
    (poo-flow-test-case "source guards require exact Unicode content and EOF"
      (with-module
        (lambda (root)
          (def file (path-expand "modules/custom/example/types.ss" root))
          (def text "aλ\nb")
          (write-role root "types" text)
          (call-with-module-source-read-cache
            (lambda ()
              (module-source-admit-current! (list (cons file text)))
              (check-equal? (module-source-read file) text)))
          (for-each (lambda (expected)
                      (check-exception (module-source-admit-current! (list (cons file expected))) error?))
                    '("aλ" "aλ\nb!" "aλ\nc" ""))
          (write-role root "types" "")
          (check-exception (module-source-admit-current! (list (cons file text))) error?)
          (module-source-admit-current! (list (cons file ""))))))
    (poo-flow-test-case "nested pure guards reuse reads but independent validation observes changes"
      (with-module
       (lambda (root)
         (let ((file (path-expand "modules/custom/example/types.ss" root))
               (reads 0) (events (make-hash-table)))
           (parameterize ((current-module-source-observer
                           (lambda (kind amount)
                             (hash-update! events kind (cut + <> amount) 0)
                             (when (eq? kind 'reads) (set! reads (+ reads 1)))))
                          (current-module-source-phase 'nested-guard))
             (let (original
                   (call-with-module-source-read-cache
                     (lambda ()
                       (let (first (module-source-read file))
                         (call-with-module-source-read-cache
                           (lambda () (check-equal? (module-source-read file) first)))
                         first))))
               (check-equal? reads 1)
               (check-equal? (hash-ref events (list 'file-read 'nested-guard file)) 1)
               (check-equal? (hash-ref events (list 'file-request 'nested-guard file)) 2)
               ;; Mutation is an effect BETWEEN validation scopes, never inside.
               (write-role root "types" "(def PublicContract 'updated)")
               (check-exception
                (call-with-module-source-read-cache
                  (lambda () (module-source-admit-current! (list (cons file original)))))
                error?)
               (check-equal? reads 2)))))))
    (poo-flow-test-case "file-kind observations expire before a later validation"
      (with-module
       (lambda (root)
         (def file (path-expand "modules/custom/example/types.ss" root))
         (def original
           (call-with-module-source-read-cache (lambda () (module-source-read file))))
         (delete-file file)
         (create-directory file)
         (check-exception
           (call-with-module-source-read-cache
             (lambda () (module-source-admit-current! (list (cons file original)))))
           error?)
         (delete-directory file)
         (create-symbolic-link (path-expand "modules/custom/example/objects.ss" root) file)
         (check-exception
           (call-with-module-source-read-cache (lambda () (module-source-read file))) error?))))
    (poo-flow-test-case "one public Module object needs no flat private re-exports"
      (with-module
       (lambda (root)
         (let (sources (collection-source root))
           (check-equal? (length sources) 1)
           (check-equal?
            (poo-flow-validation-evidence-accepted?
             (admit-module-publication! (car sources) 'custom/example (publication) (.o))) #t))
         (check-equal? (.get (directory-scope root (lambda (_source) (publication))) ready) #t))))
    (poo-flow-test-case "missing, empty, nonregular and symlinked required roles are refused"
      (for-each
       (lambda (damage)
         (with-module
          (lambda (root)
            (let (path (path-expand "modules/custom/example/types.ss" root))
              (delete-file path) (damage path root) (both-refuse root)))))
       (list (lambda (_path _root) (void))
             (lambda (path _root) (call-with-output-file path (lambda (_port) (void))))
             (lambda (path _root) (create-directory path))
             (lambda (path root) (create-symbolic-link (path-expand "modules/custom/example/objects.ss" root) path)))))
    (poo-flow-test-case "reversed role imports and forbidden config behavior fail before publication"
      (for-each
       (lambda (text)
         (with-module (lambda (root) (write-role root "config" text) (both-refuse root))))
       '("(import \"interface.ss\") (def Config 'invalid)" "(stage provider runtime)")))
    (poo-flow-test-case "objects may consume optional pure functions; func cannot import interface"
      (with-module
       (lambda (root)
         (write-role root "func" "(import \"types.ss\") (def (adjust value) value)")
         (write-role root "objects" "(import \"func.ss\") (def Defaults 'default)")
         (check-equal? (length (collection-source root)) 1)
         (check-equal? (.get (directory-scope root (lambda (_source) (publication))) ready) #t)
         (write-role root "func" "(import \"interface.ss\") (def (adjust value) value)")
         (both-refuse root))))
    (poo-flow-test-case "unselected broken siblings stay unread and optional func edits invalidate"
      (with-module
       (lambda (root)
         (write-role root "func" "(def (adjust value) value)")
         (create-directory (path-expand "modules/custom/unused" root))
         (check-equal? (length (collection-source root)) 1)
         (let (view (poo-flow-load-modules (path-expand "modules" root)
                      read-publication: (lambda (_source) (publication))))
           (check-equal? (.get view modules custom example ready) #t)
           ((.get view admit-current))
           (write-role root "func" "(def (adjust value) 'changed)")
           (check-exception ((.get view admit-current)) error?)))))
    (poo-flow-test-case "collection keys cannot escape their source and optional roles must be regular"
      (with-module
       (lambda (root)
         (let (collection (make-poo-flow-module-source-collection 'fixture 'test root "modules/custom"))
           (check-exception
            (poo-flow-module-source-collection-locate collection '(custom . ../example)) error?))
         (create-directory (path-expand "modules/custom/example/func.ss" root))
         (both-refuse root))))
    (poo-flow-test-case "source owner and publication owner must agree before scope assembly"
      (let ((source (make-poo-flow-module-source-ref
                     'local "example/interface.ss" '((module-id . another/owner))))
            (value (publication)))
        (check-exception (admit-module-publication! source 'custom/example value (.o)) error?)
        (check-exception
         (admit-module-publication! (make-poo-flow-module-generated-source 'custom/example)
                                    'custom/example (.o identity: 'custom/example) (.o)) error?)))))
