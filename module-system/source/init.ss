;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Read-only lowering of the bounded init declaration, never eval/import.
(import (only-in :clan/poo/object .o .+ .ref)
        (only-in :std/list/list any)
        (only-in :yuanxu/module-system/selection/objects yuanxu-user-module-selection))
(export module-init-intent module-init-export-name)

;; A declaration belongs to its native module identity, not its prelude, Git
;; remote or the caller's filesystem spelling. init.ss is a convention, not a
;; restriction on where yuanxu! may declare a directory window.
(def (module-init-export-name identity)
  (unless (symbol? identity) (error "init requires a native module identity" identity))
  (let (name (symbol->string identity))
    (let (separator (string-rindex name #\/))
      (string->symbol
        (string-append
          (if separator
            (string-append (substring name 0 separator) "."
                           (substring name (+ separator 1) (string-length name)))
            name)
          ".exports")))))
(def (init-name? name)
  (and (symbol? name)
       (let (text (symbol->string name))
         (and (> (string-length text) 0) (not (member text '("." "..")))
              (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list text))))))
(def (single-init-intent forms source-path (window? #f))
  (def mount-value #f)
  (let ((declarations (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms)))
    (unless (= (length declarations) 1)
      (error "init.ss requires exactly one yuanxu! declaration" source-path))
    ;; Import/export are compiler scaffolding only. No other top-level form is
    ;; silently ignored or run; computed init declarations need a separate adapter.
    (unless (andmap (lambda (form) (and (list? form) (pair? form)
                                       (memq (car form) '(import export yuanxu!)))) forms)
      (error "init.ss contains non-declarative forms" source-path))
    (let parse ((tail (cdar declarations)) (mode-value 'explicit) (root-value "modules")
                (group #f) (rows '()) (options '()) (seen '()))
      (cond
       ((null? tail)
        (unless (memq 'mode: options)
          (error "init.ss requires mode: explicit or mode: auto" source-path))
        (.o mode: mode-value root: root-value mount: mount-value init-source: source-path
            root-explicit?: (and (memq 'source: options) #t) decisions: (reverse rows)))
       ((not (pair? tail)) (error "improper init declaration" source-path))
       ((memq (car tail) '(mode: source: rename:))
        (unless (and (pair? (cdr tail)) (not group) (null? rows) (not (memq (car tail) options)))
          (error "duplicate or misplaced init option" (car tail) source-path))
        (let ((key (car tail)) (value (cadr tail)))
          (case key
            ((mode:) (unless (memq value '(auto explicit)) (error "invalid init mode" value)))
            ((source:) (unless (and (string? value) (> (string-length value) 0))
                         (error "invalid init source" value)))
            ((rename:)
             (unless (and window? (or (string? value) (symbol? value)))
               (error "rename requires a literal directory mount" value))
             (set! mount-value (if (string? value) (string->symbol value) value))))
          (parse (cddr tail) (if (eq? key 'mode:) value mode-value)
                 (if (eq? key 'source:) value root-value) group rows (cons key options) seen)))
       ((and (symbol? (car tail))
             (> (string-length (symbol->string (car tail))) 1)
             (char=? (string-ref (symbol->string (car tail)) 0) #\:))
        (unless (init-name? (string->symbol (substring (symbol->string (car tail)) 1
                                                        (string-length (symbol->string (car tail))))))
          (error "invalid init category" (car tail) source-path))
        (parse (cdr tail) mode-value root-value
               (string->symbol (substring (symbol->string (car tail)) 1
                                          (string-length (symbol->string (car tail)))))
               rows options seen))
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
            (when (memq id seen) (error "duplicate init module decision" id source-path))
            (parse (cdr tail) mode-value root-value group
                   (cons (.o identity: id disabled?: disabled-value
                             disable-specified?: disable-specified-value
                             source-root: source-root-value
                             selection: (.+ (yuanxu-user-module-selection group (car row) flags)
                                            (.o enabled?: (not disabled-value)))) rows)
                   options (cons id seen)))))))))

;; Windows normalize into the existing selection intent. Mount names route
;; values; they never rewrite publication/requirement identities.
(def (directory-window-intents body source-path)
  (match body
    ([] '())
    ([':load-modules (? string? root) . tail]
     (let split ((rest tail) (clauses '()))
       (if (or (null? rest) (eq? (car rest) ':load-modules))
         (let* ((intent (single-init-intent
                         (list `(yuanxu! source: ,root ,@(reverse clauses))) source-path #t))
                (name (or (.ref intent 'mount)
                          (string->symbol (path-strip-directory
                            (path-strip-trailing-directory-separator (path-expand root)))))))
           (unless (and (> (string-length root) 0) (not (member ".." (string-split root #\/))))
             (error "invalid directory window source" root))
           (unless (and (init-name? name)
                        (not (memq name '(build-spec build-current! test-spec test-current! tests))))
             (error "invalid or reserved directory mount" name))
           (cons (.+ intent (.o mount: name)) (directory-window-intents rest source-path)))
         (split (cdr rest) (cons (car rest) clauses)))))
    (_ (error "directory window requires a literal source path" source-path))))

(def (module-init-intent forms source-path)
  (def declarations (filter (lambda (form) (and (pair? form) (eq? (car form) 'yuanxu!))) forms))
  (unless (= (length declarations) 1) (error "init.ss requires exactly one yuanxu! declaration" source-path))
  (unless (andmap (lambda (form) (and (list? form) (pair? form)
                                    (memq (car form) '(import export yuanxu!)))) forms)
    (error "init.ss contains non-declarative forms" source-path))
  (def body (cdar declarations))
  (if (or (null? body) (not (eq? (car body) ':load-modules)))
    (single-init-intent forms source-path)
    (let ((window-values (directory-window-intents body source-path))
          (names (make-hash-table)) (roots (make-hash-table)) (ids (make-hash-table-eq)))
      (def rows
        (foldr append '()
          (map (lambda (window)
                 (def name (.ref window 'mount))
                 (def key (string-downcase (symbol->string name)))
                 (def root (path-strip-trailing-directory-separator
                             (path-expand (.ref window 'root)
                               (if source-path (path-directory source-path) (current-directory)))))
                 (when (hash-key? names key) (error "duplicate directory mount" name))
                 (when (hash-key? roots root) (error "duplicate directory window source" root))
                 (hash-put! names key #t) (hash-put! roots root #t)
                 (map (lambda (row)
                        (def id (.ref row 'identity))
                        (when (hash-key? ids id) (error "publication identity occurs in multiple windows" id))
                        (hash-put! ids id #t)
                        (.+ row (.o window: name))) (.ref window 'decisions))) window-values)))
      (.o mode: (if (any (lambda (window) (eq? (.ref window 'mode) 'auto)) window-values) 'auto 'explicit)
          root: (.ref (car window-values) 'root) root-explicit?: #t init-source: source-path
          windows: window-values decisions: rows))))
