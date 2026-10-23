;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Platform-owned admission context over existing selected/build Graph guards.
(import :clan/poo/object
        (only-in :clan/poo/mop define-type Type element?)
        (only-in :yuanxu/module-system/source/build unique-build-inputs)
        (only-in :yuanxu/module-system/building/artifacts admit-build-artifacts!
          admit-build-artifact-publication! build-artifact-publication-current)
        (only-in :yuanxu/admission/contributions bind-publication-contributions)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :std/string/path path-absolute?)
        (only-in :yuanxu/object-types/contracts yuanxu-contract-admit yuanxu-validation-evidence-accepted?
                 call-with-contract-analysis-root)
        (only-in :yuanxu/module-system/source/admission
          module-source-read module-source-admit-current! call-with-module-source-read-cache
          current-module-source-observer)
        (only-in :yuanxu/modules/json-schema/json-schema-source yuanxu-json-schema-read-port)
        (only-in :yuanxu/modules/json-schema/json-schema-normalize yuanxu-json-schema-normalize)
        (only-in :yuanxu/modules/json-schema/json-schema-ir yuanxu-json-schema-normalization->alist)
        (only-in :yuanxu/modules/json-schema/json-schema-ir yuanxu-json-schema-normalization-schema)
        (only-in :yuanxu/modules/json-schema/json-schema-receipt
          yuanxu-json-schema-contract-artifact?
          yuanxu-json-schema-contract-artifact-valid?
          yuanxu-json-schema-contract-artifact-source-ref
          yuanxu-json-schema-contract-artifact-diagnostics
          yuanxu-json-schema-contract-artifact-normalization))
(export AdmissionPublication. module-admission-publication)

(def (copy-inputs inputs)
  (map (lambda (input)
         (cons (string-copy (car input))
               (and (cdr input) (string-copy (cdr input))))) inputs))

;; Bind the artifact's actual schema to exactly the text whose revision we keep.
;; This path supports local file-backed artifacts; labels are not file versions.
(def (schema-input artifact)
  (unless (and (yuanxu-json-schema-contract-artifact? artifact)
               (yuanxu-json-schema-contract-artifact-valid? artifact)
               (null? (yuanxu-json-schema-contract-artifact-diagnostics artifact)))
    (error "admission requires a valid selected Schema artifact"))
  (let (path (yuanxu-json-schema-contract-artifact-source-ref artifact))
    (unless (and (string? path) (path-absolute? path))
      (error "Schema artifact requires an absolute source reference" path))
    (let (text (module-source-read path))
      (unless (equal?
                (yuanxu-json-schema-normalization->alist
                  (yuanxu-json-schema-normalize
                    (call-with-input-string text yuanxu-json-schema-read-port)))
                (yuanxu-json-schema-normalization->alist
                  (yuanxu-json-schema-contract-artifact-normalization artifact)))
        (error "Schema artifact no longer matches its selected source" path))
      (cons (string-copy path) text))))

;; Published Provider contracts retain their existing generated artifact and the
;; exact manifest/index/type bytes used by the digest-checked reader. Consume
;; that association instead of re-exporting Schema JSON into a temporary file.
(def (schema-observations selected)
  (if (yuanxu-json-schema-contract-artifact? selected)
    (list (schema-input selected))
    (begin
      (unless (and (object? selected)
                   (every (cut .slot? selected <>)
                     '(schema schema-artifact source-inputs)))
        (error "admission requires a Schema artifact or published Schema contract"))
      (let* ((artifact (.get selected schema-artifact))
             (inputs (.get selected source-inputs)))
        (unless (and (yuanxu-json-schema-contract-artifact? artifact)
                     (yuanxu-json-schema-contract-artifact-valid? artifact)
                     (null? (yuanxu-json-schema-contract-artifact-diagnostics artifact))
                     (eq? (.ref (if (.slot? selected 'value-type)
                                  (.get selected value-type) selected) 'node)
                       (yuanxu-json-schema-normalization-schema
                         (yuanxu-json-schema-contract-artifact-normalization artifact)))
                     (equal?
                       (yuanxu-json-schema-normalization->alist
                         (yuanxu-json-schema-normalize (.get selected schema)))
                       (yuanxu-json-schema-normalization->alist
                         (yuanxu-json-schema-contract-artifact-normalization artifact)))
                     (pair? inputs)
                     (every (lambda (input)
                              (and (pair? input) (string? (car input))
                                   (path-absolute? (car input)) (string? (cdr input)))) inputs))
          (error "published Schema contract association is incomplete or mismatched"))
        (module-source-admit-current! inputs "published Schema source changed")
        (copy-inputs inputs)))))

;; Traverse public Type edges, never candidates or the whole Module catalog.
;; Reader-produced Schema leaves retain their own source association.
(def (contract-schemas descriptor)
  (def seen (make-hash-table-eq))
  (def (walk type)
    (unless (object? type) (error "admission requires a public Type"))
    (if (hash-get seen type) '()
      (begin
        (hash-put! seen type #t)
        ;; .cc preserves the Schema protocol, not nominal ancestry. Missing
        ;; publication metadata on a Schema node must refuse, never disappear.
        (if (.slot? type 'node)
          (begin
            (unless (.slot? type 'schema-artifact)
              (error "Schema Type is missing its publication association"))
            (list type))
          (append
            (if (.slot? type 'responsibilities)
              (foldr append '()
                (map (lambda (name) (walk (.ref (.get type responsibilities) name)))
                     (.all-slots (.get type responsibilities)))) '())
            (if (.slot? type 'constraints)
              (foldr append '() (map walk (.get type constraints))) '())
            (foldr append '()
              (map (lambda (slot)
                     (if (.slot? type slot)
                       (let (value (.ref type slot))
                         ;; Context-only child Contracts intentionally have no
                         ;; public value validator. Other malformed Type edges
                         ;; must still refuse rather than hide Schema inputs.
                         (if (and (eq? slot 'value-contract) (not value))
                           '() (walk value)))
                       '()))
                   '(value-contract expected-type prepared-constraint))))))))
  (walk descriptor))

(def (scope-path scope path)
  (foldl (lambda (name value)
           (unless (and (object? value) (.slot? value name))
             (error "unresolved publication admission path" path name))
           (.ref value name)) scope path))

;; The selected, admitted Module publication owns both scope paths. Reuse its
;; actual descriptor: this creates neither a producer nor another evidence type.
(def (module-admission-publication graph publication scope name)
  (admit-build-artifacts! graph)
  ((.get graph admit-current))
  (unless (find (lambda (node)
                  (and (eq? (.get node kind) 'module-core)
                       (eq? (.get node publication) publication)))
                (.get graph selected-graph nodes))
    (error "admission publication is outside selected Graph"))
  (def core (.get publication core))
  (unless (and (.slot? core 'admissions) (.slot? (.get core admissions) name))
    (error "unknown publication admission" (.get publication identity) name))
  (def declaration (.ref (.get core admissions) name))
  (def descriptor
    (publication-stage 'resolve-descriptor
      (lambda () (scope-path scope (.get declaration contract-path)))))
  (unless (and (object? descriptor)
               (element? Type descriptor)
               (every (cut .slot? descriptor <>) '(identity .admit value-contract))
               (procedure? (.get descriptor .admit))
               (element? Type (.get descriptor value-contract)))
    (error "publication admission path requires a checked Core Contract" name))
  (.cc AdmissionPublication.
    'graph graph 'contract descriptor
    'schemas (publication-stage 'resolve-schemas (lambda () (contract-schemas descriptor)))
    'configuration-inputs (if (.slot? descriptor 'source-inputs) (.get descriptor source-inputs) '())
    'value (scope-path scope (.get declaration export-path))))

(def (admission-context build-graph artifacts inputs (defer-current? #f))
  ;; Standalone construction is an admission boundary. The private assembler
  ;; already admitted requests at export entry and will admit the full Context
  ;; before return; its intermediate source collection is not a publication.
  (unless defer-current? ((.get build-graph admit-current)))
  (let* ((selected (.get build-graph selected-graph))
         (generation (.get build-graph generation))
         (sources (copy-inputs (unique-build-inputs (append (.get build-graph source-inputs) inputs))))
         ;; Capture metadata outside the read window: a cold getter may run
         ;; code. Then check compiler AND request/configuration observations
         ;; together before demanding any Schema associations. Reuse neither
         ;; these bytes nor this incomplete Context across the Schema getters.
         (_source-entry
          (when defer-current?
            (call-with-module-source-read-cache
              (lambda ()
                ((.get build-graph compiler-current))
                (module-source-admit-current! sources "admission source input changed")))))
         (schemas (publication-stage 'schema-associations
                   (lambda ()
                     (unique-build-inputs
                       (foldr append '() (map schema-observations artifacts)))))))
    (def (current!)
      (admit-build-artifacts! build-graph)
      ;; The build Graph guard is source-only; package checks live separately
      ;; at publication's effect boundaries. Do not encompass Contract callbacks
      ;; or Nix in this synchronous observation window.
      (call-with-module-source-read-cache
        (lambda ()
          ((.get build-graph admit-current))
          (unless (and (eq? selected (.get build-graph selected-graph))
                       (equal? generation (.get selected generation)))
            (error "admission belongs to a different selected Graph"))
          (module-source-admit-current! sources "admission source input changed")
          (module-source-admit-current! schemas "admission Schema input changed")
          ((.get build-graph admit-current))
          (admit-build-artifacts! build-graph))))
    ;; Only the private .for-export assembly defers this check to its
    ;; enclosing contribution binder, which admits the complete Context before
    ;; returning it. Ordinary Context construction keeps its return guard.
    (unless defer-current? (current!))
    (.o selected-graph: selected graph-generation: generation
        source-inputs: sources schema-inputs: schemas admit-current: current!)))

(def (evidence-view evidence)
  (.o subject: (.get evidence candidate)
      descriptor: (.get evidence admission-contract)
      context: (.get evidence context)))

(def AdmissionCall
  (metadata.contract
    (metadata.predicate "configuration object" object?)
    (metadata.predicate "accepted Core evidence" yuanxu-validation-evidence-accepted?)
    (lambda (_key _request _evidence) #t)
    (metadata.atom 'context-current)))

(def (publication-stage name thunk)
  ;; Passive attribution only: never share observations across these callbacks.
  (let (observer (current-module-source-observer))
    (if (not observer) (thunk)
      (dynamic-wind
        (lambda () (observer (list 'admission-stage-start name) 1))
        thunk
        (lambda () (observer (list 'admission-stage-end name) 1))))))

(def (publication-invocation context-value)
  (metadata.with-meaning AdmissionCall
    (lambda (_key _request _evidence)
      (publication-stage 'meaning-current (.get context-value admit-current)) #t) #f))

(def (publish-current publication previous candidate)
  (let ((descriptor (.get publication contract))
        (context-value (.get publication context))
        (package-current (.get publication package-current))
        (current-call (.get publication invocation)))
    (metadata.publish current-call previous
      (lambda (value)
        ;; Runs on every invocation, including a previously demanded context.
        (publication-stage 'entry-current (.get context-value admit-current))
        ;; Nix/package effects must not run under the source-read cache used by
        ;; contextual child checks. Recheck the package before and after admission.
        (when package-current
          (publication-stage 'package-before package-current)
          ;; This recheck belongs to the package callback, not to admission
          ;; itself. With no package callback, entry-current already completed
          ;; this boundary; the producer still checks Context after obligations.
          (publication-stage 'post-package-current (.get context-value admit-current)))
        (def evidence
          (publication-stage 'contract-admit
            (lambda ()
              ;; The publisher owns this one root producer invocation, including
              ;; ordinary public value Contracts without a source wrapper.
              ;; The kernel consumes the exact edge before any open callback;
              ;; only its registered responsibility children inherit analysis.
              ;; Root, independent and replaced/inherited Context callbacks keep
              ;; their full source guards. This is not a byte-cache window.
              (call-with-contract-analysis-root descriptor value context-value
                (cut yuanxu-contract-admit descriptor value context-value)))))
        (def checked (.get evidence candidate))
        (def bound
          (publication-stage 'bind-evidence
            (cut .call publication .bind-evidence checked)))
        (metadata.invoke bound
          (lambda (_checked)
            ;; Rejected evidence cannot publish. Let the public invocation
            ;; Contract report its output refusal without a second external
            ;; package query. Accepted evidence still crosses this effect boundary.
            (when (and package-current (yuanxu-validation-evidence-accepted? evidence))
              (publication-stage 'package-after package-current))
            ;; The bound invocation checks currentness in its dependent meaning
            ;; after this source returns. Checking here would misclassify a
            ;; post-admission Context refusal as an executor/source failure.
            (values evidence checked)) checked))
      candidate)))

;; The platform supplies the selected build Graph and its published Schema
;; contracts (or file-backed artifacts). Users do not pass version/Context records.
(define-type (AdmissionPublication. @ [] graph schemas contract context invocation configuration-inputs package-current)
  .for-export:
  (lambda (selection owner name)
    ;; Reject a stale managed build before resolving an export scope, whose
    ;; lazy fields may run author code. Native cache state grants no shortcut.
    (admit-build-artifact-publication! (.get selection build-graph))
    (let (record (publication-stage 'selected-record
                   (lambda () (.call selection .selected-record owner))))
      (publication-stage 'bind-contributions
        (lambda ()
          (let* ((base (module-admission-publication (.get selection build-graph)
                         (.get record publication) (.get record scope) name))
                 (package-guard
                   (let ((build-current (build-artifact-publication-current (.get selection build-graph)))
                         (packages-current (.get selection package-current)))
                     (if (and build-current packages-current)
                       (lambda () (build-current) (packages-current))
                       (or build-current packages-current)))))
            (bind-publication-contributions selection owner name
              (.o (:: @ base graph schemas configuration-inputs)
                ;; No intermediate Context escapes this assembly. The binder's
                ;; final current! includes this base's complete source/Schema
                ;; guard plus the contribution checks; do not run it twice.
                context: (admission-context graph schemas configuration-inputs #t)
                package-current: package-guard)))))))
  package-current: #f
  configuration-inputs: '()
  context: (admission-context graph schemas configuration-inputs)
  invocation: (publication-invocation context)
  ;; Return the existing public invocation Contract, with this publication's
  ;; actual references. Binding neither admits a value nor runs package effects;
  ;; full Core publication continues to use .publish below.
  .bind-evidence:
  (lambda (subject)
    (metadata.bind-evidence invocation subject contract context evidence-view))
  .publish: (lambda (previous candidate)
              (publish-current @ previous candidate)))
