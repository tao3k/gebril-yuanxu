;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Field diagnostics reuse JSON baselines and native winning slot provenance.
(import :clan/poo/object
        (only-in :yuanxu/configuration/json config-field-origin))
(export config-diagnostic-locator)

(def (field-value object path)
  (foldl (lambda (name value)
           (if (and (object? value) (.slot? value name)) (.ref value name) 'missing))
         object path))
(def (relative-path prefix path)
  (cond ((null? prefix) path)
        ((and (pair? path) (eq? (car prefix) (car path)))
         (relative-path (cdr prefix) (cdr path)))
        (else #f)))

;; documents maps the immediate owner slots below root to their JSON documents.
;; No field table is copied from a Contract and no candidate tree is scanned.
(def (config-diagnostic-locator documents root)
  (def (origin candidate path observe?)
    (def tail (relative-path root path))
    (and (pair? tail) (.slot? documents (car tail))
      (let (effective (field-value candidate (append root (list (car tail)))))
        (config-field-origin (.ref documents (car tail)) (cdr tail)
          (if observe? (field-value effective (cdr tail)) 'unobserved)
          effective))))
  (lambda (candidate failure)
    ;; A contextual refusal is a receipt, not a field diagnostic. Leave its
    ;; Contract, candidate identity and responsibility lineage untouched.
    (if (and (object? failure) (not (.slot? failure 'admission-contract))
             (.slot? failure 'path))
      (let (located (origin candidate (.get failure path)
                     (not (and (.slot? failure 'kind)
                               (eq? (.get failure kind) 'unknown-field)))))
        (if located
          (let (issue (.cc failure origin: located))
            (let (expected
                   (and (.slot? failure 'expected-path)
                        (origin candidate (.get failure expected-path) #t)))
              (if expected (.cc issue expected-origin: expected) issue)))
          failure))
      failure)))
