;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Read-only lowering of the bounded init declaration, never eval/import.
(import (only-in :clan/poo/object .o .+)
        (only-in :core/module-system/selection/objects poo-flow-user-module-selection))
(export module-init-intent)
(def (init-name? name)
  (and (symbol? name)
       (let (text (symbol->string name))
         (and (> (string-length text) 0) (not (member text '("." "..")))
              (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list text))))))
(def (module-init-intent forms source-path)
  (let ((declarations (filter (lambda (form) (and (pair? form) (eq? (car form) 'poo-flow!))) forms)))
    (unless (= (length declarations) 1)
      (error "init.ss requires exactly one poo-flow! declaration" source-path))
    ;; Import/export are compiler scaffolding only. No other top-level form is
    ;; silently ignored or run; computed init declarations need a separate adapter.
    (unless (andmap (lambda (form) (and (list? form) (pair? form)
                                       (memq (car form) '(import export poo-flow!)))) forms)
      (error "init.ss contains non-declarative forms" source-path))
    (let parse ((tail (cdar declarations)) (mode-value 'explicit) (root-value "modules")
                (group #f) (rows '()) (options '()) (seen '()))
      (cond
       ((null? tail)
        (.o mode: mode-value root: root-value init-source: source-path root-explicit?: (and (memq 'source: options) #t) decisions: (reverse rows)))
       ((not (pair? tail)) (error "improper init declaration" source-path))
       ((memq (car tail) '(mode: source:))
        (unless (and (pair? (cdr tail)) (not group) (not (memq (car tail) options)))
          (error "duplicate or misplaced init option" (car tail) source-path))
        (let ((key (car tail)) (value (cadr tail)))
          (case key
            ((mode:) (unless (memq value '(auto explicit)) (error "invalid init mode" value)))
            ((source:) (unless (and (string? value) (> (string-length value) 0))
                         (error "invalid init source" value))))
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
          (unless (and group (list? row) (pair? row) (init-name? (car row)))
            (error "expected a categorized module row" row source-path))
          (let* ((id (string->symbol (string-append (symbol->string group) "/" (symbol->string (car row)))))
                 (disabled-value #f)
                 (disable-specified-value #f)
                 (flags
                  (let flags-loop ((rest (cdr row)) (result '()) (disable-seen? #f))
                    (cond
                     ((null? rest) (reverse result))
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
                        (when (or (memq flag result) (memq opposite result))
                          (error "conflicting init feature decisions" row source-path))
                        (flags-loop (cdr rest) (cons flag result) disable-seen?)))
                     (else (error "unsupported init flag or computed source" row source-path))))))
            (when (memq id seen) (error "duplicate init module decision" id source-path))
            (parse (cdr tail) mode-value root-value group
                   (cons (.o identity: id disabled?: disabled-value
                             disable-specified?: disable-specified-value
                             selection: (.+ (poo-flow-user-module-selection group (car row) flags)
                                            (.o enabled?: (not disabled-value)))) rows)
                   options (cons id seen)))))))))
