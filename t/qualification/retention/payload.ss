;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Read-only census of already surviving records. Never demand a native slot.
(import :clan/poo/object
        (only-in :clan/poo/slot-observation slot-read-key slot-read-receiver)
        (only-in :clan/poo/mop Class. Slot. Type.)
        (only-in :clan/poo/method-combination Contribution.)
        (only-in :yuanxu/object-types/contracts YuanxuClassificationEvidence YuanxuValidationEvidence)
        (only-in :gerbil/expander expander-context?)
        (only-in :gerbil/runtime/interface interface-instance? interface-instance-object)
        (rename-in (only-in :gerbil/runtime/gambit table?) (table? weak-table?)))
(export report-retained-reads)
(extern namespace: clan/poo/method-combination registered-contribution)

;; The qualified installed arm64 VM uses 8-byte words and 4-byte characters.
;; Count actual native body fields; exclude headers/padding and opaque leaves.
;; This is ABI-specific payload accounting, not portable allocator statistics.
(def (object-body-bytes value)
  (cond ((pair? value) 16)
        ((vector? value) (* 8 (vector-length value)))
        ((string? value) (* 4 (string-length value)))
        ((##closure? value) (* 8 (##closure-length value)))
        ((##structure? value) (* 8 (##structure-length value)))
        (else 0)))

;; Identity union of actual read bodies and already allocated receiver-local
;; metadata/specification payload. POO referents, Gerbil contexts, type descriptors
;; and GC tables are frontiers. Never scan the Gerbil through a captured closure.
;; This is a bounded BODY-byte census, not dominator/exclusive heap attribution.
(def (payload-bytes reads owners)
  (def seen (make-hash-table-eq))
  (def frontiers (make-hash-table-eq))
  (def bytes 0)
  (def shells 0)
  (def body-kinds (make-hash-table-eq))
  (def stage 'start)
  (def issuer-code (make-hash-table-eq))
  (for-each
    (lambda (read)
      (defvalues (_shown original _signed _snapshot _shape) (object-read-issuance read))
      (when (and original (##closure? original))
        (hash-put! issuer-code (##subprocedure-parent (##closure-ref original 0)) #t))) reads)
  (def (sdk-record? value)
    (and (##structure? value)
      (let (id (##type-id (##structure-type value)))
        (and (symbol? id)
          (let (name (symbol->string id))
            (or (string-prefix? "gx#" name) (string-prefix? "gxc#" name)
                (string-prefix? "gerbil/expander/" name)))))))
  (def (walk value)
    (cond
      ((or (begin (set! stage 'object) (object? value))
           (begin (set! stage 'expander) (expander-context? value))
           (begin (set! stage 'class) (class-type? value))
           (begin (set! stage 'table) (weak-table? value))
           (##continuation? value) (sdk-record? value)
           (and (##structure? value)
                (##structure-instance-of? value 'gerbil#__gc-table::t)))
       (hash-put! frontiers value #t))
      ((and (or (pair? value) (vector? value) (string? value)
                (##closure? value) (##structure? value))
            (not (hash-key? seen value)))
       (set! stage 'account)
       (hash-put! seen value #t)
       (let ((size (object-body-bytes value))
             (kind (cond ((pair? value) 'pairs) ((vector? value) 'vectors)
                         ((string? value) 'strings) ((##closure? value) 'closures)
                         (else 'structures))))
         (set! bytes (+ bytes size))
         (hash-update! body-kinds kind (cut + <> size) 0))
       (cond
         ((pair? value) (walk (car value)) (walk (cdr value)))
         ((vector? value)
          (let loop ((index 0))
            (when (< index (vector-length value))
              (walk (vector-ref value index)) (loop (1+ index)))))
         ((##closure? value)
          ;; Only the actual native issuer's code family owns this private
          ;; capture projection. An arbitrary callback may capture a whole VM
          ;; environment, including the running probe; keep that frontier opaque.
          (if (hash-key? issuer-code (##subprocedure-parent (##closure-ref value 0)))
            (let loop ((index 1))
              (when (< index (##closure-length value))
                (walk (##closure-ref value index)) (loop (1+ index))))
            (hash-put! frontiers value #t)))
         ;; Interface method tables are shared Gerbil implementation, not this
         ;; receiver's payload. Follow its actual backing object only.
         ((interface-instance? value) (walk (interface-instance-object value)))
         ((##structure? value)
          (let ((type (##structure-type value)))
            (let loop ((index 1))
              (when (< index (##structure-length value))
                (walk (##structure-ref value index type #f)) (loop (1+ index))))))))))
  (with-catch
    (lambda (cause) (displayln "RETAINED-PROBE-FAILURE " stage) (raise cause))
    (lambda () (for-each walk reads)))
  (hash-for-each
    (lambda (owner _)
      (set! shells (+ shells (object-body-bytes owner)))
      (with-catch
        (lambda (cause) (displayln "RETAINED-PROBE-FAILURE " stage) (raise cause))
        (lambda () (for-each walk
        (list (object-%reads owner) (object-%instance owner) (object-%layout owner)
              (object-%slot-funs owner) (object-%slots owner) (object-%defaults owner)
              (object-%state owner)))))) owners)
  (list (cons 'body-bytes (+ bytes shells)) (cons 'receiver-shell-bytes shells)
        (cons 'payload-identities (hash-length seen))
        (cons 'opaque-frontiers (hash-length frontiers))
        (cons 'abi '(word64 char32))
        (cons 'body-kinds (hash->list body-kinds))))

(def (report-retained-reads label weak)
  (def rows (make-hash-table))
  (def owners (make-hash-table-eq))
  (def field-maps (make-hash-table-eq))
  ;; These two declarations are module-global native Types. Follow only their
  ;; already computed native metadata, never a candidate or a cold getter.
  (def schema-owners (make-hash-table-eq))
  (def (schema! descriptor)
    (when (and (object? descriptor) (not (hash-key? schema-owners descriptor)))
      (hash-put! schema-owners descriptor #t)
      (let (fields (object-%instance descriptor))
        (when fields
          (for-each (lambda (key)
                      (let (mapping (hash-get fields key))
                        (when (object? mapping)
                          (hash-put! schema-owners mapping #t)
                          (let (entries (object-%instance mapping))
                            (when entries
                              (hash-for-each (lambda (_value slot) (schema! slot)) entries))))))
            '(slots effective-slots))
          (schema! (hash-get fields 'type))))))
  (schema! YuanxuClassificationEvidence)
  (schema! YuanxuValidationEvidence)
  (def schema-reads 0)
  (hash-for-each
    (lambda (read _)
      (def receiver (slot-read-receiver read))
      (when (hash-key? schema-owners receiver) (set! schema-reads (1+ schema-reads)))
      (when (memq Class. (or (object-%precedence-list receiver) '()))
        (let (fields (object-%instance receiver))
          (when fields
            (for-each (lambda (key)
                        (let (value (hash-get fields key))
                          (when (object? value) (hash-put! field-maps value #t))))
              '(slots effective-slots)))))) weak)
  (hash-for-each
    (lambda (read _)
      (def receiver (slot-read-receiver read))
      (def fields (and (object? receiver) (object-%instance receiver)))
      (def kind (and fields (hash-get fields 'kind)))
      (def identity (and fields (hash-get fields 'identity)))
      (def precedence (or (object-%precedence-list receiver) '()))
      (def family
        (cond ((symbol? kind) kind) ((symbol? identity) identity)
              ((hash-key? field-maps receiver) 'native-record-field-map)
              ((or (registered-contribution receiver) (memq Contribution. precedence))
               'native-method-contribution)
              ((memq Slot. precedence) 'native-record-slot)
              ((memq Class. precedence) 'native-record-descriptor)
              ((memq Type. precedence) 'native-type)
              (else 'anonymous)))
      (def key (slot-read-key read))
      (def key-label (if (pair? key) (list (car key) (length key)) key))
      (hash-put! owners receiver #t)
      (hash-update! rows (list family key-label) 1+ 0)) weak)
  (for-each
    (lambda (row) (displayln (object->string (list 'RETAINED-READ label (car row) (cdr row)))))
    (list-sort (lambda (a b) (string<? (object->string (car a)) (object->string (car b))))
      (hash->list rows)))
  (displayln (object->string (list 'RETAINED-OWNERS label (hash-length owners))))
  (displayln (object->string (list 'RETAINED-SHARED-SCHEMA label schema-reads)))
  (displayln (object->string (cons 'RETAINED-PAYLOAD
    (cons label (payload-bytes (hash-keys weak) owners))))))
