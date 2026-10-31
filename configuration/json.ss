;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; JSON is data, never evaluated identifiers or procedures.
(import :clan/poo/object
        (only-in :std/encoding/json JSONReadOptions current-json-read-options read-json)
        (only-in :std/list/walist PureAList? walist->list)
        (only-in :yuanxu/configuration/slot-origin field-slot-origins/value)
        (only-in :yuanxu/module-system/source/admission module-source-read module-source-admit-current!))
(export config-json-file config-defaults config-field-origin current-configuration-input-observer)
;; A reader-local capability; ordinary callers do not maintain asset lists.
(def current-configuration-input-observer (make-parameter #f))
(def (native-data value)
  (cond ((PureAList? value)
         (object<-alist (map (lambda (row) (cons (car row) (native-data (cdr row)))) (walist->list value))))
        ((vector? value) (map native-data (vector->list value)))
        ((list? value) (map native-data value))
        ((or (void? value) (memq value '(null json-null))) 'json-null)
        (else value)))
(def (config-json-file path)
  (def source-path (path-normalize (path-expand path)))
  (def text (module-source-read source-path))
  (def parsed-value
    (call-with-input-string text
      (lambda (port)
        (parameterize ((current-json-read-options (JSONReadOptions key-as-symbol: #t)))
          (def result (native-data (read-json port)))
          (let loop ((char (read-char port)))
            (unless (eof-object? char)
              (unless (char-whitespace? char) (error "trailing JSON data" source-path))
              (loop (read-char port))))
          result))))
  (unless (object? parsed-value) (error "configuration JSON must be an object" source-path))
  (def inputs (list (cons source-path text)))
  (module-source-admit-current! inputs "configuration JSON changed")
  (when (current-configuration-input-observer)
    ((current-configuration-input-observer) source-path text))
  (.o value: parsed-value source: source-path source-inputs: inputs))
;; Only missing fields inherit. Explicit null/scalars replace an entire subtree.
(def (config-defaults defaults supplied)
  (if (and (object? defaults) (object? supplied))
    (object<-alist
      (map (lambda (name)
             (cons name
               (if (.slot? defaults name)
                 (config-defaults (.ref defaults name) (.ref supplied name))
                 (.ref supplied name))))
           (.all-slots supplied))
      supers: (list defaults))
    supplied))
;; A JSON source locator, not a fabricated Scheme assignment span.
(def (json-field-origin document field-path actual-value)
  (let loop ((value (.get document value)) (tail field-path) (prefix '()))
    (cond
     ((null? tail)
      (.o source: (.get document source) path: field-path
          presence: (if (eq? value 'json-null) 'null 'explicit)
          kind: (if (equal? value actual-value) 'json-field 'derived-value)))
     ((and (object? value) (.slot? value (car tail)))
      (loop (.ref value (car tail)) (cdr tail) (cons (car tail) prefix)))
     ((not (object? value))
      (.o source: (.get document source) path: (reverse prefix)
          requested-path: field-path
          presence: (if (eq? value 'json-null) 'null 'explicit) kind: 'json-field))
     (else
      (.o source: (.get document source) path: field-path presence: 'missing kind: 'default)))))

;; The same field diagnostic keeps its JSON baseline and native derivation chain.
(def (config-field-origin document field-path actual-value (effective #f))
  (def baseline (json-field-origin document field-path actual-value))
  (def origins (if effective (field-slot-origins/value effective field-path) '()))
  (if (null? origins) baseline
    (.cc (car origins) path: field-path baseline: baseline
         derived-from: (cdr origins) presence: 'explicit)))
