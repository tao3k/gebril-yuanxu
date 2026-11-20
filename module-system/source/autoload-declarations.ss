;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core

;;; Compiled modules publish declarations under their compiler-owned ID.
;;; Gerbil resolves and initializes the module before its values can be read.
(import (only-in :clan/poo/type Type. Symbol define-type validate)
        (only-in :gerbil/runtime/loader load-module)
        (for-syntax :gerbil/expander))
(export define-yuanxu-module-declaration yuanxu-module-declaration YuanxuLibraryModule)

(def (library-module? value)
  (and (symbol? value)
       (let* ((spelling (symbol->string value)) (size (string-length spelling)))
         (and (> size 1) (char=? (string-ref spelling 0) #\:)
              (not (char=? (string-ref spelling (1- size)) #\/))
              (andmap (lambda (part)
                        (and (not (member part '("" "." "..")))
                             (not (string-index part #\\))
                             (not (string-index part (integer->char 0)))))
                      (string-split (substring spelling 1 size) #\/))))))

(define-type (YuanxuLibraryModule @ Type.)
  identity: 'yuanxu/library-module
  .element?: library-module?)

(def declarations (make-hash-table))
(def declaration-lock (make-mutex 'module-declarations))

(def (publish-module-declaration! owner name value)
  (with-lock declaration-lock
    (lambda () (hash-put! declarations (cons owner name) value))))

(defsyntax (define-yuanxu-module-declaration stx)
  (syntax-case stx ()
    ((_ name value)
     (identifier? #'name)
     (let (context (core-context-top (current-expander-context) module-context?))
       (unless context (raise-syntax-error #f "expected a library module" stx))
       (with-syntax ((owner (expander-context-id context)))
         #'(begin
             (def name value)
             (publish-module-declaration! 'owner 'name name)))))
    (_ (raise-syntax-error #f "expected a declaration name and value" stx))))

(def (yuanxu-module-declaration specifier binding contract directory: (directory (current-directory)))
  (let* ((spelling (symbol->string (validate YuanxuLibraryModule specifier)))
         (owner (substring spelling 1 (string-length spelling)))
         (key (cons (string->symbol owner) (validate Symbol binding))))
    (parameterize ((current-directory (path-expand directory)))
      (load-module owner))
    (validate contract (with-lock declaration-lock (lambda () (hash-ref declarations key))))))
