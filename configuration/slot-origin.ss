;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Private provenance lives on native specifications, not in a field registry.
(import (runtime: :clan/poo/object)
        (only-in :clan/poo/prototype-map prototype-map-ref)
        (only-in :std/list/list delete-duplicates/hash every)
        (only-in :yuanxu/module-system/source/admission
                 module-source-type module-source-read module-source-admit-current!
                 call-with-module-source-read-cache))
(export source-object-slots field-slot-origins/value admit-field-sources!)
(defstruct (located-slot $computed-slot-spec) (location inputs) final: #t)
;; False metadata is still a present attribution barrier. Use a private absence
;; identity, never a value predicate or a second index of public field names.
(def absent-specification (gensym 'absent-specification))

;; Called only on a fresh authoring object. Wrapping a specification does not
;; invoke it, its inherited computation, or any other field.
(def (source-object-slots object rows)
  ;; Defaults are not winning direct method specifications. In particular a
  ;; native method/default pair must never relabel the method as its default.
  (def methods (filter (lambda (row) (not (eq? (list-ref row 4) '?))) rows))
  (def paths (delete-duplicates/hash (filter-map (lambda (row) (cadr row)) methods)))
  ;; Value construction remains usable without installed sources (e.g. AOT).
  ;; Source-bound admission below must refuse an unavailable observation.
  (def inputs
    (map (lambda (path)
           ;; One private requirement batch per source file. Distinct native
           ;; specifications/locations retain their own identities while
           ;; sharing this unchanged snapshot, rather than reboxing its row
           ;; once per field and repeating collector enrollment at replay.
           (cons path (list (cons path
             (and (eq? (module-source-type path) 'regular)
                  (module-source-read path)))))) paths))
  (for-each
    (lambda (row)
      (let (spec (prototype-map-ref (object-%slots object) (car row) absent-specification))
        (when (and (not (eq? spec absent-specification)) (cadr row))
          (.putslot! object (car row)
            (make-located-slot
              (lambda (self next) ((apply-slot-spec self spec next)))
              row (cdr (assoc (cadr row) inputs)))))))
    methods)
  object)

(defstruct slot-sources (visible observed opaque?) final: #t)
;; One read-only MOP query for every operation. A runtime assignment or an
;; unknown winning specification is an attribution barrier, not an older source.
;; Retain observed ancestor specifications for conservative currentness checks.
(def (slot-origins object name)
  ;; Read-only traversal borrows existing native metadata. Do not allocate a
  ;; public snapshot merely to discard it; cold preparation still owns hooks.
  (unless (object-%precedence-list object)
    (compute-precedence-list! object))
  (def assigned? (and (object-%overrides object) (hash-key? (object-%overrides object) name)))
  (let loop ((parents (object-%precedence-list object))
             (visible '()) (observed '()) (open? (not assigned?)) (declared? assigned?))
    (if (null? parents)
      (make-slot-sources (reverse visible) (reverse observed)
        (and declared? (null? visible)))
      (let* ((parent (car parents))
             (spec (prototype-map-ref (object-%slots parent) name absent-specification))
             (method? (not (eq? spec absent-specification)))
             (declaration? (and (not method?)
               (not (eq? (prototype-map-ref (object-%declarations parent) name absent-specification)
                         absent-specification)))))
        (cond
         ((and method? (located-slot? spec))
          (loop (cdr parents) (if open? (cons spec visible) visible)
                (cons spec observed) open? #t))
         ((or method? declaration?)
          (loop (cdr parents) visible observed #f #t))
         (else (loop (cdr parents) visible observed open? declared?)))))))

;; Walk the requested object path only. Keep the deepest known declaration;
;; A known ancestor cannot supply an exact locator for an opaque child write.
(def (field-slot-origins object path)
  (let walk ((value object) (tail path) (found '()))
    (if (or (null? tail) (not (object? value))) found
      (let* ((name (car tail)) (sources (slot-origins value name))
             (here (slot-sources-visible sources))
             (next (cond
                    ((slot-sources-opaque? sources) '())
                    ((and (pair? here)
                            (or (null? (cdr tail))
                                (eq? (list-ref (located-slot-location (car here)) 4) 'assign)))
                     here)
                    (else found))))
        (if (or (null? (cdr tail)) (not (.slot? value name))) next
          (walk (.ref value name) (cdr tail) next))))))

(def (admit-origins! origins)
  ;; A specification's retained inputs are data. Share physical observations
  ;; across inherited specifications here, ending BEFORE any slot getter runs.
  ;; In particular, the recursive path walker below must stay outside this
  ;; window: an intermediate getter may mutate source or perform other effects.
  (unless (null? origins)
    (call-with-module-source-read-cache
      (lambda ()
        (for-each
          (lambda (spec)
            (unless (every (lambda (entry) (string? (cdr entry))) (located-slot-inputs spec))
              (error "Scheme configuration source unavailable" (located-slot-location spec)))
            (module-source-admit-current! (located-slot-inputs spec)
              "Scheme configuration source changed")) origins)))))
(def (admit-field-sources! object paths)
  (for-each
    (lambda (path)
      (let walk ((value object) (tail path))
        (when (and (object? value) (pair? tail))
          (admit-origins! (slot-sources-observed (slot-origins value (car tail))))
          (when (and (pair? (cdr tail)) (.slot? value (car tail)))
            (walk (.ref value (car tail)) (cdr tail)))))) paths))

;; Expose a value projection, never the private snapshot or mutable specification.
(def (origin-value spec)
  (let (row (located-slot-location spec))
    (.o kind: 'scheme-slot source: (cadr row)
        line: (caddr row) column: (cadddr row)
        operation: (list-ref row 4))))
(def (field-slot-origins/value object path)
  (let (origins (field-slot-origins object path))
    (admit-origins! origins)
    (map origin-value origins)))
