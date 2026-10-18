;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Platform-owned admission context over existing selected/build Graph guards.
(import :clan/poo/object
        (only-in :clan/poo/mop define-type Type element?)
        (only-in :core/module-system/source/build unique-build-inputs)
        (only-in :core/admission/contributions bind-publication-contributions)
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :std/string/path path-absolute?)
        (only-in :core/types poo-flow-contract-admit poo-flow-validation-evidence-accepted?)
        (only-in :core/module-system/source/admission
          module-source-read module-source-admit-current! call-with-module-source-read-cache)
        (only-in :core/modules/json-schema/json-schema-source poo-flow-json-schema-read-port)
        (only-in :core/modules/json-schema/json-schema-normalize poo-flow-json-schema-normalize)
        (only-in :core/modules/json-schema/json-schema-ir poo-flow-json-schema-normalization->alist)
        (only-in :core/modules/json-schema/json-schema-ir poo-flow-json-schema-normalization-schema)
        (only-in :core/modules/json-schema/json-schema-receipt
          poo-flow-json-schema-contract-artifact?
          poo-flow-json-schema-contract-artifact-valid?
          poo-flow-json-schema-contract-artifact-source-ref
          poo-flow-json-schema-contract-artifact-diagnostics
          poo-flow-json-schema-contract-artifact-normalization))
(export AdmissionPublication. module-admission-publication)

(def (copy-inputs inputs)
  (map (lambda (input)
         (cons (string-copy (car input))
               (and (cdr input) (string-copy (cdr input))))) inputs))

;; Bind the artifact's actual schema to exactly the text whose revision we keep.
;; This path supports local file-backed artifacts; labels are not file versions.
(def (schema-input artifact)
  (unless (and (poo-flow-json-schema-contract-artifact? artifact)
               (poo-flow-json-schema-contract-artifact-valid? artifact)
               (null? (poo-flow-json-schema-contract-artifact-diagnostics artifact)))
    (error "admission requires a valid selected Schema artifact"))
  (let (path (poo-flow-json-schema-contract-artifact-source-ref artifact))
    (unless (and (string? path) (path-absolute? path))
      (error "Schema artifact requires an absolute source reference" path))
    (let (text (module-source-read path))
      (unless (equal?
                (poo-flow-json-schema-normalization->alist
                  (poo-flow-json-schema-normalize
                    (call-with-input-string text poo-flow-json-schema-read-port)))
                (poo-flow-json-schema-normalization->alist
                  (poo-flow-json-schema-contract-artifact-normalization artifact)))
        (error "Schema artifact no longer matches its selected source" path))
      (cons (string-copy path) text))))

;; Published Provider contracts retain their existing generated artifact and the
;; exact manifest/index/type bytes used by the digest-checked reader. Consume
;; that association instead of re-exporting Schema JSON into a temporary file.
(def (schema-observations selected)
  (if (poo-flow-json-schema-contract-artifact? selected)
    (list (schema-input selected))
    (begin
      (unless (and (object? selected)
                   (every (cut .slot? selected <>)
                     '(schema schema-artifact source-inputs)))
        (error "admission requires a Schema artifact or published Schema contract"))
      (let* ((artifact (.get selected schema-artifact))
             (inputs (.get selected source-inputs)))
        (unless (and (poo-flow-json-schema-contract-artifact? artifact)
                     (poo-flow-json-schema-contract-artifact-valid? artifact)
                     (null? (poo-flow-json-schema-contract-artifact-diagnostics artifact))
                     (eq? (.ref (if (.slot? selected 'value-type)
                                  (.get selected value-type) selected) 'node)
                       (poo-flow-json-schema-normalization-schema
                         (poo-flow-json-schema-contract-artifact-normalization artifact)))
                     (equal?
                       (poo-flow-json-schema-normalization->alist
                         (poo-flow-json-schema-normalize (.get selected schema)))
                       (poo-flow-json-schema-normalization->alist
                         (poo-flow-json-schema-contract-artifact-normalization artifact)))
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
  (def descriptor (scope-path scope (.get declaration contract-path)))
  (unless (and (object? descriptor)
               (element? Type descriptor)
               (every (cut .slot? descriptor <>) '(identity .admit value-contract))
               (procedure? (.get descriptor .admit))
               (element? Type (.get descriptor value-contract)))
    (error "publication admission path requires a checked Core Contract" name))
  (.cc AdmissionPublication.
    'graph graph 'contract descriptor 'schemas (contract-schemas descriptor)
    'configuration-inputs (if (.slot? descriptor 'source-inputs) (.get descriptor source-inputs) '())
    'value (scope-path scope (.get declaration export-path))))

(def (admission-context build-graph artifacts inputs)
  ((.get build-graph admit-current))
  (let ((selected (.get build-graph selected-graph))
        (generation (.get build-graph generation))
        (sources (copy-inputs (unique-build-inputs (append (.get build-graph source-inputs) inputs))))
        (schemas (unique-build-inputs
                   (foldr append '() (map schema-observations artifacts)))))
    (def (current!)
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
          ((.get build-graph admit-current)))))
    (current!)
    (.o selected-graph: selected graph-generation: generation
        source-inputs: sources schema-inputs: schemas admit-current: current!)))

(def (evidence-view evidence)
  (.o subject: (.get evidence candidate)
      descriptor: (.get evidence admission-contract)
      context: (.get evidence context)))

(def AdmissionCall
  (metadata.contract
    (metadata.predicate "configuration object" object?)
    (metadata.predicate "accepted Core evidence" poo-flow-validation-evidence-accepted?)
    (lambda (_key _request _evidence) #t)
    (metadata.atom 'context-current)))

(def (publish-current previous candidate descriptor context-value package-current)
  (let ((current-call
           (metadata.with-meaning AdmissionCall
             (lambda (_key _request _evidence)
               ((.get context-value admit-current)) #t) #f)))
    (metadata.publish current-call previous
      (lambda (value)
        ;; Runs on every invocation, including a previously demanded context.
        ((.get context-value admit-current))
        ;; Nix/package effects must not run under the source-read cache used by
        ;; contextual child checks. Recheck the package before and after admission.
        (when package-current (package-current))
        ((.get context-value admit-current))
        (def evidence (poo-flow-contract-admit descriptor value context-value))
        (def checked (.get evidence candidate))
        (def bound
          (metadata.bind-evidence current-call checked descriptor context-value evidence-view))
        (metadata.invoke bound
          (lambda (_checked)
            (when package-current (package-current))
            ;; The bound invocation checks currentness in its dependent meaning
            ;; after this source returns. Checking here would misclassify a
            ;; post-admission Context refusal as an executor/source failure.
            (values evidence checked)) checked))
      candidate)))

;; The platform supplies the selected build Graph and its published Schema
;; contracts (or file-backed artifacts). Users do not pass version/Context records.
(define-type (AdmissionPublication. @ [] graph schemas contract context configuration-inputs package-current)
  .for-export:
  (lambda (selection owner name)
    (let (record (.call selection .selected-record owner))
      (bind-publication-contributions selection owner name
        (.cc (module-admission-publication (.get selection build-graph)
                (.get record publication) (.get record scope) name)
          'package-current (.get selection package-current)))))
  package-current: #f
  configuration-inputs: '()
  context: (admission-context graph schemas configuration-inputs)
  .publish: (lambda (previous candidate)
              (publish-current previous candidate contract context package-current)))
