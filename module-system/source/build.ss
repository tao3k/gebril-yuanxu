;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Selected Graph/runtime test demand -> observed compiler inputs. No compilation or execution.
(import (only-in :tao3k/yuanxu/module-system/source/link call-with-linked-prepared-guards)
        (only-in :tao3k/yuanxu/module-system/building/configuration-source configuration-request-current/owned)
        (only-in :gerbil/expander current-expander-context make-top-context eval-syntax
                 core-import-module __module-registry expander-context-id module-context-path
                 core-read-module core-expand-module-begin make-module-context
                 core-module->prelude-context module-context? prelude-context?
                 make-prelude-context current-expander-module-prelude
                 current-expander-path current-expander-marks current-expander-phi
                 current-import-expander-phi current-export-expander-phi raise-syntax-error)
        (only-in :tao3k/yuanxu/module-system/building/source-closure for-each-build-module package-library-spec/source-context)
        (only-in :tao3k/yuanxu/module-system/building/source-package package-prelude-identity)
        (only-in :tao3k/yuanxu/module-system/building/program-products make-target-spec program-targets)
        (only-in :tao3k/yuanxu/module-system/source/deferred-declaration module-binding-action)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/string/path path-absolute? path-default-extension subpath?)
        (only-in :std/list/list find foldl)
        (only-in :clan/poo/slot-observation without-observation %slot-read-active?)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :tao3k/yuanxu/object-family/read-projection owned-read-function-scope?)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/mop define-type Type.)
        (only-in :clan/poo/type List)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :tao3k/yuanxu/module-system/source/admission admit-module-value! module-source-type module-source-read module-source-name? module-source-admit-current! call-with-module-source-read-cache module-source-observe module-source-object-policy current-module-source-phase current-module-source-observer module-source-measure-operation call-with-module-source-callback)
        (only-in :tao3k/yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source
                 build-target-name yuanxu-prepare-module-retained-source module-compiler-source-owner?
                 module-source-package-info)
        (only-in :tao3k/yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata)
        (only-in :tao3k/yuanxu/module-system/source/publication requirement-option)
        (only-in :tao3k/yuanxu/module-system/feature/capability-model feature-projection-request?)
        (only-in :tao3k/yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :tao3k/yuanxu/module-system/building/package write-selected-package))
(export module-test-source-spec module-build-graph module-build-graph/linked unique-build-inputs retained-build-entries ExternalPackageContributionContract BuildSpecContract
        BuildPublicationContract module-build-admit-context!
        module-build-package-inputs-current! module-build-package-source-check
        module-build-package-source-procedure module-build-package-source-inspector)
(define-type (BuildPublicationContract @ Type.)
  identity: 'module/build-publication
  .element?: (lambda (value)
               (and (object? value) (.slot? value '.restore-build)
                    (procedure? (.ref value '.restore-build)))))
(def (build-root? value)
  (or (and (string? value) (> (string-length value) 0))
      (and (list? value) (>= (length value) 2) (eq? (car value) 'gxc:)
           (string? (cadr value)) (> (string-length (cadr value)) 0)
           (andmap string? (cddr value)))))
;; Executables are native Make products, not test-only demands. Their source
;; ownership and currentness are checked by the enclosing projection.
(def (make-target? value)
  (or (build-root? value)
      (and (list? value) (>= (length value) 2) (eq? (car value) 'exe:)
           (string? (cadr value)) (> (string-length (cadr value)) 0)
           (let (options (cddr value))
             (if (and (pair? options) (eq? (car options) 'bin:))
               (and (pair? (cdr options)) (string? (cadr options))
                    (module-source-name? (cadr options)) (andmap string? (cddr options)))
               (andmap string? options))))))
(define-type (MakeTargetContract @ Type.)
  identity: 'module/make-target .element?: make-target?)
;; Pure native-spec shape and composition. Source/publication authentication
;; remains in the enclosing init-owned boundary, never in a claimed origin tag.
(def BuildSpecContract
  (.cc ObjectContract. identity: 'module/build-spec
    responsibilities:
    (.o module-spec: (List MakeTargetContract)
        retained-spec: (List MakeTargetContract)
        spec: (List MakeTargetContract))
    obligations:
    (lambda (candidate location)
      ;; Count actual obligation execution, not just its caller's wrapper.
      ;; A second validate inside one boundary must count twice as well.
      (module-source-measure-operation 'build-spec-contract
        (lambda ()
          (def spec (.ref candidate 'spec))
          (if (not (equal? spec
                           (append (.ref candidate 'module-spec) (.ref candidate 'retained-spec))))
            (list (.o kind: 'build-spec-merge-mismatch path: (append location '(spec))))
            (let ((seen (make-hash-table)) (issues '()) (index 0))
              (for-each
                (lambda (target)
                  (def kind (if (string? target) gxc: (car target)))
                  (def name (if (string? target) target (cadr target)))
                  (def (note! key)
                    (if (hash-key? seen key)
                      (set! issues
                        (cons (.o kind: 'duplicate-std-make-target
                                  path: (append location (list 'spec index))
                                  target: key first: (hash-ref seen key) repeated: target) issues))
                      (hash-put! seen key target)))
                  ;; STD Make rejects a repeated Scheme source independently
                  ;; of the requested product or its options.
                  (note! (list 'source (path-default-extension name ".ss")))
                  (when (eq? kind exe:)
                    (note! (list 'binary (pgetq bin: (cddr target) (path-strip-directory name)))))
                  (set! index (+ index 1))) spec)
              (reverse issues))))))))
(define-type (ExternalPackageContributionContract @ Type.)
  identity: 'module/external-package
  .element?: (lambda (value)
      (and (object? value)
           (andmap (cut .slot? value <>) '(kind identity .prepare))
           (eq? (.ref value 'kind) 'module/external-package)
           (symbol? (.ref value 'identity))
           (module-source-name? (symbol->string (.ref value 'identity)))
           (procedure? (.ref value '.prepare)))))
(def (confined-build-path root relative)
  (unless (and (string? relative) (not (path-absolute? relative))
               (andmap module-source-name? (string-split relative #\/)))
    (error "build contribution must name an owner-relative source" root relative))
  (let walk ((directory root) (parts (string-split (path-default-extension relative ".ss") #\/)))
    (let ((path (path-expand (car parts) directory)))
      (unless (eq? (module-source-type path) (if (pair? (cdr parts)) 'directory 'regular))
        (error "build source is missing, non-regular or a symlink" path))
      (if (pair? (cdr parts)) (walk path (cdr parts)) path))))
(def (unique-build-inputs observations)
  (let ((seen (make-hash-table)) (result '()))
    (for-each
     (lambda (entry)
       (if (hash-key? seen (car entry))
         (unless (equal? (hash-ref seen (car entry)) (cdr entry))
           (error "inconsistent build input snapshots" (car entry)))
         (begin (hash-put! seen (car entry) (cdr entry)) (set! result (cons entry result))))) observations)
    (reverse result)))
;; Only the Build Graph constructor issues this carrier. It retains no
;; currentness result. A derived graph or a replacement guard cannot use it.
(defstruct build-context-frame (owner guard check) final: #t)

(def (check-context-inputs! graph selected generation sources schemas (cached #f))
  (unless (if cached
            (and (eq? selected (cached graph 'selected-graph))
                 (equal? generation (cached selected 'generation)))
            (and (eq? selected (.ref graph 'selected-graph))
                 (equal? generation (.ref selected 'generation))))
    (error "admission belongs to a different selected Graph"))
  (module-source-admit-current! sources "admission source input changed")
  (module-source-admit-current! schemas "admission Schema input changed"))

(def (current-build-context-frame graph)
  (and (not (or (current-module-source-observer) (%slot-read-active?)))
       (object-construction-current?) (owned-read-function-scope?)
       (with-catch (lambda (_unsupported) #f)
         (lambda ()
           (without-observation
             (lambda ()
               (and (object? graph) (object-%instance graph) (object-%precedence-list graph)
                    (not (object-protocol graph))
                    (begin
                      (require-read-route! 'admission-context #f (object-%instance graph))
                      (let (value (.ref/cached graph '%admission-frame (lambda () #f)))
                        (and (build-context-frame? value)
                             (eq? graph (build-context-frame-owner value))
                             (eq? (build-context-frame-guard value)
                                  (.ref/cached graph 'admit-current (lambda () #f)))
                             value))))))))))

(def (module-build-admit-context! graph selected generation sources schemas)
  (def (ordinary!)
    ((.ref graph 'admit-current))
    (check-context-inputs! graph selected generation sources schemas)
    ((.ref graph 'admit-current)))
  (def frame (current-build-context-frame graph))
  (if frame
    ((build-context-frame-check frame) selected generation sources schemas ordinary!)
    (ordinary!)))

;; The producer supplies source rows. The guard body is owned here, so a
;; caller cannot enroll a replacement procedure as a native source check.
(defstruct build-package-source-check (graph invoke) final: #t)
(def (module-build-package-inputs-current! graph observed inputs)
  (call-with-module-source-read-cache
    (lambda ()
      (.call graph admit-current)
      (module-source-admit-current! observed)
      (module-source-admit-current! inputs))))
(def (module-build-package-source-check graph observed inputs entry)
  (def (invoke)
    (module-build-package-inputs-current! graph observed inputs)
    (module-source-admit-current! entry))
  (make-build-package-source-check graph invoke))
(def (module-build-package-source-procedure check)
  (build-package-source-check-invoke check))
(def (module-build-package-source-inspector)
  (lambda (result graph)
    (and (not (or (current-module-source-observer) (%slot-read-active?)))
         (owned-read-function-scope?)
         (with-catch (lambda (_unsupported) #f)
           (lambda ()
             (without-observation
               (lambda ()
                 (and (object? result) (object-%instance result)
                      (object-%precedence-list result) (not (object-protocol result))
                      (begin
                        (require-read-route! 'package-sources #f (object-%instance result))
                        (let ((check (.ref/cached result '%package-source-check (lambda () #f)))
                              (invoke (.ref/cached result 'sources-current (lambda () #f)))
                              (frame (current-build-context-frame graph)))
                          (and frame (build-package-source-check? check)
                               (eq? graph (build-package-source-check-graph check))
                               (eq? invoke (build-package-source-check-invoke check))
                               invoke)))))))))))

(def (module-build-graph selected-value prepare-publication (source-window #f) (source-state #f))
  (module-build-graph/linked selected-value prepare-publication source-window source-state #f))
(def (module-build-graph/linked selected-value prepare-publication source-window source-state support)
  (parameterize ((current-module-build-phase? #t))
    (module-build-graph/phase selected-value prepare-publication source-window source-state support)))
(def (module-build-graph/phase selected-value prepare-publication source-window source-state support)
  (parameterize ((current-module-source-phase 'build-entry))
    ((.ref selected-value 'admit-current)))
  (let ((entry-values '()) (by-path (make-hash-table)) (by-id (make-hash-table-eq))
        (prepared (make-hash-table)) (checks '()) (check-inputs '()) (other '())
        (asset-values '()) (asset-paths (make-hash-table))
        (native-targets (make-hash-table))
        (native-binaries (make-hash-table))
        (library-sources (make-hash-table))
        (package-values '()) (package-demands '()) (library-demands '()) (package-refused? #f)
        (package-ids (make-hash-table-eq))
        (cores (make-hash-table-eq)) (owned-graph #f) (graph-policy #f) (entry-construction-intact? (object-construction-current?)))
    ;; Index the already-selected Core nodes once; dependency edges select
    ;; configuration builders, never a second directory/provider scan.
    (for-each (lambda (node)
                (when (eq? (.ref node 'kind) 'module-core)
                  (hash-put! cores (.ref node 'owner) (.ref (.ref node 'publication) 'core))))
              (.ref selected-value 'nodes))
    (def (add-check! input)
      (set! check-inputs (cons input check-inputs))
      (set! checks (cons (.ref input 'admit-current) checks)))
    (def (check-current! observed-checks)
      (if (and support (pair? observed-checks) (eq? observed-checks checks))
        (call-with-linked-prepared-guards support selected-value
          check-inputs observed-checks bound-input-state)
        (begin
          ((.ref selected-value 'admit-current))
          (for-each (lambda (check) (check)) observed-checks))))
    (def (current! (site 'build-current))
      (parameterize ((current-module-source-phase site))
        (call-with-module-source-read-cache
          (lambda ()
            ;; Cache only this pure traversal in the enclosing observation
            ;; window. Adding an input changes the key; effects and independent
            ;; currentness calls start fresh windows, never reuse this approval.
            (module-source-observe check-current! checks)))))
    (def (owner-preparation owner)
      (if (hash-key? prepared owner) (hash-ref prepared owner)
        (let (value (prepare-publication owner))
          (unless (and (.slot? value 'generation)
                       (equal? (.ref value 'generation) (.ref selected-value 'generation))
                       (eq? (.ref value 'identity) owner))
            (error "build source belongs to a different selected Graph" owner))
          (hash-put! prepared owner value)
          (add-check! value) value)))
    (def (add! kind input owner contributor (library? #t))
      (let* ((path (if (eq? kind 'publication)
                      (.ref (.ref input 'source) 'value) (.ref input 'path)))
             (compiler-identity (.ref input 'compiler-identity))
             (target (hash-get native-targets path))
             (options (if (and (pair? target) (eq? (car target) gxc:)) (cddr target) '())))
        (when library? (hash-put! library-sources path #t))
        (cond
         ((hash-key? by-path path)
          (let (old (hash-ref by-path path))
            (unless (eq? kind (.ref old 'kind))
              (error "conflicting build contributions" path (.ref old 'contributor) contributor))))
         ((hash-key? by-id compiler-identity)
          (error "duplicate compiler identity in selected build Graph" compiler-identity path
                 (.ref (hash-ref by-id compiler-identity) 'path)))
         (else
          ;; These are immutable captures, not receiver-dependent formulas.
          ;; Runtime lexical slots retain the same values without getter closures.
          (set! entry-construction-intact?
            (and entry-construction-intact? (object-construction-current?)))
          (let (entry (.o kind path compiler-identity input options owner contributor))
            (set! entry-construction-intact?
              (and entry-construction-intact? (object-construction-current?)))
            (hash-put! by-path path entry) (hash-put! by-id compiler-identity entry)
            (add-check! input)
            (set! entry-values (cons entry entry-values)))))))
    (def (add-asset! input-value owner-id)
      (def file (.ref input-value 'path))
      (when (hash-key? asset-paths file)
        (error "duplicate selected configuration asset" file owner-id))
      (hash-put! asset-paths file #t)
      (add-check! input-value)
      (set! asset-values (cons (.cc input-value owner: owner-id) asset-values)))
    ;; current! validates the selected context once before these local guards.
    ;; Capturing it again per entry makes each check recursively rewalk all Modules.
    ;; Local guards still re-read bytes/package identity on every boundary.
    (def (prepare-source path)
      (cond ((hash-get by-path path) => (cut .ref <> 'input))
            (else
             (yuanxu-prepare-module-build-source path void
               capture: (lambda (value checker path ready? state)
                          (when state (hash-put! by-id value state)) value)))))
    (def (add-source! path owner contributor (observed-input #f) (library? #t))
      (add! 'source (or observed-input (prepare-source path)) owner contributor library?))
    ;; Package public entries belong to their declaring Module. Gerbil supplies
    ;; the actual import graph; the existing preparer guards every local source.
    ;; Owner-relative roots remain confined and keep their explicit options.
    (def (add-library! publication sources owner contributor (program-source #f))
      (def directory (path-directory (.ref publication 'path)))
      (def binding (module-source-package-info directory))
      (def package-root (and binding (path-normalize (car binding))))
      (unless package-root (error "public library entries require runtime package metadata" owner))
      (def package (pgetq package: (cadr binding) #f))
      (def source-prefix (string-append (path-strip-trailing-directory-separator package-root) "/"))
      (def entries
        (map (lambda (path)
               (unless (and (string? path) (string-prefix? source-prefix path))
                 (error "collected source leaves its Gerbil package" owner contributor path))
               (substring path (string-length source-prefix) (string-length path))) sources))
      (unless (symbol? package) (error "public library entries require a runtime package identity" owner))
      ;; Confine before expansion, including every unresolved path part.
      (def prefix (string-append (symbol->string package) "/"))
      (def language (package-prelude-identity package-root))
      (def (owned? identity)
        (and (symbol? identity)
             (or (eq? identity language)
                 (string-prefix? prefix (symbol->string identity)))))
      (for-each
        (lambda (entry)
          (def path (confined-build-path package-root entry))
          (def input (prepare-source path))
          (unless (string-prefix? prefix (symbol->string (.ref input 'compiler-identity)))
            (error "public library entry belongs to another runtime package" path))
          (when (hash-get native-targets path)
            (add-source! path owner contributor input (not (equal? path program-source)))))
        entries)
      (def (admit-context context)
        (def identity (expander-context-id context))
        (when (owned? identity)
          (let* ((relative (build-target-name identity (symbol->string package) language))
                 (path (confined-build-path package-root relative))
                 (actual (module-context-path context)))
            (unless (and (string? actual) (equal? path (path-normalize actual)))
              (error "public library compiler source differs from declared package" identity path actual))
            ;; The executable root was enrolled above. Its imports are
            ;; libraries unless they were independently declared as programs.
            (unless (equal? path program-source)
              (add-source! path owner contributor)))))
      (def (declared-source-context context)
        (let ((identity (expander-context-id context))
              (actual (module-context-path context)))
          (if (and (owned? identity) (string? actual)
                   (string=? (path-extension actual) ".ssi"))
            ;; A compiled dependency may be this consumer's hot product.
            ;; Expand the confined source before traversing its imports.
            (let* ((relative (build-target-name identity (symbol->string package) language))
                   (path (confined-build-path package-root relative))
                   (source (core-import-module path)))
              (unless (eq? identity (expander-context-id source))
                (error "public library compiler identity differs from declared package" identity path))
              source)
            context)))
      (package-library-spec/source-context package-root package
        (map (cut path-default-extension <> ".ss") entries)
        admit-context declared-source-context))
    (def (add-package! owner contributor projection (provider #f))
      (admit-module-value! ExternalPackageContributionContract projection selected-value)
      (let* ((publication (owner-preparation owner))
             (metadata (yuanxu-module-source-ref-metadata (.ref publication 'source)))
             (root (or (assq 'module-root metadata) (assq 'module-tree-root metadata)))
             (id (.ref projection 'identity))
             ;; Bound filesystem names even for deep module identities. The
             ;; tuple remains in readable provenance; duplicate/digest collisions
             ;; reject below, never alias two consumer requests or caches.
             (key (if provider
                    (string->symbol
                     (string-append "configuration-"
                       (hex-encode (sha256 (string->utf8
                         (call-with-output-string (cut write (list provider owner id) <>)))))))
                    id)))
        (unless root (error "external package has no admitted configuration root" owner provider))
        (when (hash-key? package-ids key)
          (error "conflicting external package contributions" id owner provider contributor))
        (when provider (owner-preparation provider))
        (let (request ((.ref projection '.prepare) (cdr root) (.ref selected-value 'admit-current) publication))
          (unless (and (object? request)
                       (andmap (cut .slot? request <>) '(identity source-inputs input-files admit-current .realize))
                       (eq? (.ref request 'identity) id)
                       (list? (.ref request 'source-inputs))
                       (list? (.ref request 'input-files))
                       (procedure? (.ref request 'admit-current))
                       (procedure? (.ref request '.realize)))
            (error "malformed prepared external package" id owner provider))
          (hash-put! package-ids key #t)
          (def bound
            (if provider
              (.cc request 'identity key 'package-identity id
                   'build-owner provider 'configuration-owner owner 'dependency-alias contributor)
              (.cc request 'scope-owner owner)))
          (when (.slot? bound '%configuration-check)
            (.ref bound '%configuration-check)
            (.ref bound 'admit-current))
          (set! package-values (cons bound package-values)))))
    (def (add-configuration-builds! owner requirements)
      (for-each
       (lambda (alias)
         (let* ((requirement (.ref requirements alias))
                (provider ((.ref selected-value 'resolve-module-id) owner (.ref requirement 'module-id)))
                (baseline (hash-ref cores provider)))
           (when (and (not (requirement-option requirement 'view)) (.slot? baseline 'configuration-build))
             (set! package-demands
               (cons (lambda () (add-package! owner alias (.ref baseline 'configuration-build) provider))
                     package-demands)))))
       (.all-slots requirements)))
    (def (add-projections! owner contributor-value projections)
      (unless (list? projections) (error "module projections must be a list" contributor-value))
      (for-each
       (lambda (projection)
         (cond
          ((and (object? projection) (.slot? projection 'kind)
                (eq? (.ref projection 'kind) 'module/external-package))
           (set! package-demands
             (cons (lambda () (add-package! owner contributor-value projection)) package-demands)))
          ((list? projection)
           ;; A Module's Build binding is an ordinary std/make specification.
           ;; Keep native product kinds and option values; only source ownership
           ;; and confinement belong to this collection boundary.
           (let* ((publication (owner-preparation owner))
                  (metadata (yuanxu-module-source-ref-metadata (.ref publication 'source)))
                  (root (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
             (unless root (error "build specification has no admitted source root" owner))
             (for-each
               (lambda (spec)
                 (unless (make-target? spec) (error "invalid Module Make target" spec))
                 (let* ((name (if (string? spec) spec (cadr spec)))
                        (kind (if (string? spec) gxc: (car spec)))
                        (options (if (string? spec) '() (cddr spec)))
                        (path (confined-build-path (cdr root) name))
                        (program? (eq? kind exe:)))
                   (cond ((hash-get native-targets path)
                          => (lambda (previous)
                               (if (equal? previous spec)
                                 (error "duplicate Module Make target" owner contributor-value spec)
                                 (error "conflicting Module Make targets" previous spec)))))
                   (when program?
                     (let* ((binary (pgetq bin: options (path-strip-directory name)))
                            (old (hash-get native-binaries binary)))
                       (when old (error "programs share one binary output" binary old path))
                       (hash-put! native-binaries binary path)))
                   (hash-put! native-targets path spec)
                   ;; Traverse actual imports after explicit selected options
                   ;; are known, using the existing native source graph walker.
                   (set! library-demands
                     (cons (list publication (list path) owner contributor-value
                                 (and program? path)) library-demands))))
               projection)))
          ((feature-projection-request? projection)
           ;; A build request still needs an admitted concrete build contribution.
           (when (eq? (.ref projection 'projection-id) 'build)
             (error "unresolved build projection request" contributor-value projection))
           (set! other (cons (.o contributor: contributor-value request: projection) other)))
          (else (error "unknown or malformed selected projection" contributor-value projection)))) projections))
    ;; Resolve target options before enrolling any compiler input. Imports
    ;; and roles may encounter an explicitly configured source in any order.
    (def nodes (.ref selected-value 'nodes))
    (for-each
     (lambda (node)
       (let ((owner (.ref node 'owner)) (contributor (.ref node 'identity)))
         (case (.ref node 'kind)
           ((module-core)
            (let (core (.ref (.ref node 'publication) 'core))
              (when (.slot? core 'projections)
                (add-projections! owner contributor (.ref core 'projections)))))
           ((feature)
            (when (.ref node 'interface)
              (set! library-demands
                (cons (list (owner-preparation owner) (list (.ref node 'interface)) owner contributor)
                      library-demands)))
            (add-projections! owner contributor (.ref (.ref node 'descriptor) 'projections)))
           (else (error "unknown selected Graph node" node))))) nodes)
    (for-each
     (lambda (node)
       (when (eq? (.ref node 'kind) 'module-core)
         (let ((owner (.ref node 'owner)) (contributor (.ref node 'identity)))
            (let* ((publication (owner-preparation owner))
                   (core (.ref (.ref node 'publication) 'core))
                   (inputs (and (.slot? publication 'source-dependencies)
                                (.ref publication 'source-dependencies))))
              (when (.slot? core 'build-entries)
                (error "Core build entries are derived from roles; declare only additional projections" owner))
              ;; Preserve the existing compiler order and identity checks. The
              ;; reader has already prepared these roles under its source guard;
              ;; reuse that exact input instead of parsing/retaining it twice.
              (for-each (lambda (path)
                          (add-source! path owner contributor
                            (and inputs
                                 (find (lambda (input)
                                         (equal? (.ref input 'path) path))
                                       inputs))))
                        (.ref publication 'role-sources))
              (when inputs
                (for-each (lambda (input)
                            (if (and (.slot? input 'kind) (eq? (.ref input 'kind) 'data))
                              (add-asset! input owner)
                              (add! 'source input owner contributor)))
                          inputs))
              (add! 'publication publication owner contributor)
              (add-configuration-builds! owner (.ref core 'requires)))))) nodes)
    (for-each (lambda (request) (apply add-library! request)) (reverse library-demands))
    (set! library-demands '())
    (def entry-policy
      (and entry-construction-intact? (module-source-object-policy entry-values)))
    (def (bound-input-state input)
      (or (hash-get by-id input) (and source-state (source-state input))))
    (def (compiler-prefix predicate entries)
      (let loop ((rest entries) (prefix '()))
        (if (and (pair? rest) (predicate (car rest)))
          (loop (cdr rest) (cons (car rest) prefix))
          (reverse prefix))))
    (def (with-compiler-source-import entry input importer target identity action)
      ;; The original compiler row owns this exact entry. Do not demand a cold
      ;; input.path getter merely to rediscover its already indexed path.
      (call-with-module-source-callback
        (lambda ()
          (def import-kind
            (with-catch (lambda (_unsupported) #f)
              (lambda ()
                (and (not (current-module-source-observer)) (owned-read-function-scope?)
                 (without-observation
                  (lambda ()
                    (and source-window graph-policy entry-policy
                         (eq? importer core-import-module) (string? target)
                         (object-construction-current?) (graph-policy) (entry-policy)
                         (object? entry) (object-%instance entry) (object-%precedence-list entry)
                         (not (object-protocol entry))
                         (let (path (.ref/cached entry 'path (lambda () #f)))
                           (and (string? path) (eq? entry (hash-get by-path path))
                                (module-compiler-source-owner? owned-graph path)
                                (eq? input (.ref/cached entry 'input (lambda () #f)))
                                (begin
                                  (require-read-route! 'compiler-module-cache __module-registry #f)
                                  (let (context (or (hash-get __module-registry target)
                                                    (hash-get __module-registry (path-normalize target))))
                                    (and (module-context? context)
                                         (eq? identity (expander-context-id context))
                                         (case (.ref/cached entry 'kind (lambda () #f))
                                           ((publication) 'publication)
                                           ((source)
                                            ;; Only this Graph's constructor can
                                            ;; bind a void-context source checker.
                                            ;; Reader-derived inputs keep the full
                                            ;; Link qualification; kind alone is
                                            ;; never a claim of purity.
                                            (let (state (hash-get by-id input))
                                              (and state (state) 'input)))
                                           (else #f))))))))))))))
          (if (not import-kind) (action)
            (module-source-measure-operation 'compiler-import-cache-hit
              (lambda ()
                (if (eq? import-kind 'input)
                  ;; Both original guards still execute. They are precisely
                  ;; check-source! from prepare-build-source with native void.
                  ;; They have no Link/MOP closure to authenticate or skip.
                  (module-source-measure-operation 'compiler-source-input-shared
                    (lambda () (call-with-module-source-read-cache action)))
                  (source-window (list entry) (list input) action bound-input-state))))))))
    (def (with-compiler-source-reads batch action)
      (def (owned? entry)
        (with-catch (lambda (_unsupported) #f)
         (lambda () (without-observation
          (lambda ()
            (and (object? entry) (object-%instance entry) (object-%precedence-list entry)
                 (not (object-protocol entry))
                 (begin
                   (require-read-route! 'compiler-entry #f (object-%instance entry))
                   (let (path (.ref/cached entry 'path (lambda () #f)))
                     (and (string? path) (eq? entry (hash-get by-path path)))))))))))
      (def (run segment)
        ;; An intervening foreign entry may have replaced metadata. Recheck the
        ;; captured native policy before EVERY closed segment, not just entry.
        (if (not (and (object-construction-current?) graph-policy (graph-policy) (entry-policy)))
          (action segment)
          (let ()
        ;; The final publication's ORIGINAL guards remain outside the shared
        ;; interval. Native MOP replay and all source bytes are fresh there.
        (def boundary
          (without-observation
            (lambda ()
              (foldl (lambda (entry last)
                       (if (eq? (.ref entry 'kind) 'publication) entry last))
                     (car (reverse segment)) segment))))
        (def prefix (compiler-prefix (lambda (entry) (not (eq? entry boundary))) segment))
        (unless (null? prefix)
          (source-window prefix
            (without-observation (lambda () (map (cut .ref <> 'input) prefix)))
            (lambda () (action prefix)) bound-input-state))
        ;; The publication fence itself remains a fresh original guard. Its
        ;; source-only suffix is another segment, not permission to carry this
        ;; interval across the fence. Requalify actual metadata before sharing
        ;; that suffix; its final input remains fresh too. Every entry keeps
        ;; its original position and invokes its original guard exactly once.
        (let (tail (memq boundary segment))
          (action (list (car tail)))
          (when (pair? (cdr tail)) (run (cdr tail)))))))
      (if (not (and source-window entry-policy graph-policy (object-construction-current?)
                    (graph-policy) (entry-policy)
                    (or (null? batch)
                        (module-compiler-source-owner? owned-graph (.ref (car batch) 'path)))))
        (action batch)
        (let loop ((rest batch))
          (unless (null? rest)
            (let (segment (compiler-prefix owned? rest))
              (if (null? segment)
                (begin (action (list (car rest))) (loop (cdr rest)))
                (begin (run segment) (loop (list-tail rest (length segment))))))))))
    (def (admit-graph! graph (midpoint #f) (midpoint-ready? #f) (fallback #f))
      (def (ordinary!)
        (current! 'build-admit-before)
        ;; Observe the actual getter/callback boundary, not a reconstructed
        ;; request tree. Position is diagnostic only; do not read identity
        ;; slots here and contaminate a surrounding admission's MOP reads.
        (let loop ((requests (.ref graph 'external-packages)) (position 0))
          (unless (null? requests)
            ;; Request getters, observers and admission procedures may
            ;; change source inputs. The Graph tail must read fresh bytes.
            (call-with-module-source-callback
              (lambda ()
                (let ((observer (current-module-source-observer))
                      (name (list 'build-request position)))
                  (def (admit-request!) ((.ref (car requests) 'admit-current)))
                  (if observer
                    (dynamic-wind
                      (lambda () (observer (list 'admission-stage-start name) 1))
                      admit-request!
                      (lambda () (observer (list 'admission-stage-end name) 1)))
                    (admit-request!)))))
            (loop (cdr requests) (+ position 1))))
        (current! 'build-admit-after))
      (def (native-checks (midpoint-ready? #f))
        (and support (eq? graph owned-graph) graph-policy (graph-policy)
             (object-construction-current?) (owned-read-function-scope?)
             (not (or (current-module-source-observer) (%slot-read-active?)))
             (with-catch (lambda (_unsupported) #f)
               (lambda ()
                 (without-observation
                   (lambda ()
                     ;; Never demand a cold getter or an open request to
                     ;; discover whether its closed half can be used.
                     (let/cc unavailable
                       (def (cached receiver key)
                         (unless (and (object? receiver) (object-%instance receiver)
                                      (object-%precedence-list receiver) (not (object-protocol receiver)))
                           (unavailable #f))
                         (require-read-route! 'configuration-request #f (object-%instance receiver))
                         (.ref/cached receiver key (lambda () (unavailable #f))))
                       (when midpoint-ready? (midpoint-ready? cached unavailable))
                       (def requests (cached graph 'external-packages))
                       (and (pair? requests)
                            (let (context (cached selected-value 'admit-current))
                              (map (lambda (request)
                                     (or (configuration-request-current/owned
                                           (cached request '%configuration-check)
                                           context (cached request 'admit-current))
                                         (unavailable #f)))
                                   requests))))))))))
      (def native (native-checks midpoint-ready?))
      (def (check-request! check!)
        (module-source-measure-operation 'native-configuration-request
          (lambda ()
            (parameterize ((current-module-source-phase 'build-admit-before)) (check!))
            (for-each (lambda (admit!) (admit!)) native)
            (parameterize ((current-module-source-phase 'build-admit-after)) (check!)))))
      (def (fallback!) (if fallback (fallback) (ordinary!)))
      (if native
        (call-with-linked-prepared-guards support selected-value check-inputs checks bound-input-state
          (lambda (check!)
            (check-request! check!)
            (when midpoint
              ;; Both checks still run in order. Share the native replay
              ;; protection only around the fixed Context source obligations.
              (midpoint)
              (check-request! check!)))
          fallback!)
        (fallback!)))
    (def (context-frame graph)
      (make-build-context-frame graph (.ref graph 'admit-current)
        (lambda (selected generation sources schemas fallback)
          (def (ready? cached unavailable)
            (unless (and (eq? selected (cached graph 'selected-graph))
                         (equal? generation (cached selected 'generation)))
              (unavailable #f)))
          (def (cached receiver key)
            (.ref/cached receiver key
              (lambda () (error "admission graph changed within the source check" key))))
          (admit-graph! graph
            (lambda () (check-context-inputs! graph selected generation sources schemas cached))
            ready? fallback))))
    (let ((init-inputs
           ;; Finalization only reads the init source. Share the existing pure
           ;; window for its two Graph checks; close it before any consumer can
           ;; demand external packages, runtime imports or publication effects.
           (call-with-module-source-read-cache
             (lambda ()
               (current! 'build-finalize)
               (let* ((path (.ref selected-value 'init-source))
                      (inputs (if (and (string? path) (eq? (module-source-type path) 'regular))
                                (list (cons path (module-source-read path))) '())))
                 (current! 'build-finalize)
                 inputs)))))
      (def graph-construction-intact? (object-construction-current?))
      (def value
        (.o (:: graph) compiler-inputs:
          (unique-build-inputs
           (append init-inputs
                   (foldr append '() (map (cut .ref <> 'source-inputs) asset-values))
                   (foldr append '()
                          (map (lambda (entry) (.ref (.ref entry 'input) 'source-inputs))
                               (reverse entry-values)))))
          selected-graph: selected-value generation: (.ref selected-value 'generation)
          build-publication:
          (let (owners (filter (lambda (owner)
                                (.slot? (hash-ref cores owner) 'build-publication))
                              (hash-keys cores)))
            (cond ((null? owners) #f)
                  ((pair? (cdr owners)) (error "conflicting selected build publications" owners))
                  (else
                   (let (value (.ref (hash-ref cores (car owners)) 'build-publication))
                     (admit-module-value! BuildPublicationContract value selected-value)
                     value))))
          assets: (reverse asset-values)
          .package: (lambda (directory) (write-selected-package graph directory))
          entries: (reverse entry-values) other-projections: (reverse other)
          ;; A compiler input can appear only once in STD Make. A source
          ;; required as a library cannot also be an executable target.
          std-make-targets:
          (filter-map
            (lambda (entry)
              (def path (.ref entry 'path))
              (def target (hash-get native-targets path))
              (cond
               (target
                (when (and (pair? target) (eq? (car target) exe:)
                           (hash-get library-sources path))
                  (error "Module Make source is both a library and an executable" path))
                (cons path target))
               ((hash-get library-sources path)
                (cons path `(gxc: ,path ,@(.ref entry 'options))))
               (else #f)))
            entries)
          ;; A single Graph, with independent compiler and operational demand.
          ;; Compiler projection never prepares provider configuration or scope.
          external-packages:
          (begin
            (when package-refused? (error "external package projection was refused"))
            (with-catch
              (lambda (failure) (set! package-refused? #t) (raise failure))
              (lambda ()
                (parameterize ((current-module-build-phase? #t))
                  (current! 'build-external-before)
                  (for-each (lambda (prepare!) (prepare!)) (reverse package-demands))
                  (current! 'build-external-after)
                  (reverse package-values)))))
          source-inputs:
          (unique-build-inputs
            (append compiler-inputs
                    (foldr append '() (map (cut .ref <> 'source-inputs) external-packages))))
          compiler-current: current!
          .with-compiler-source-reads: with-compiler-source-reads
          .with-compiler-source-import: with-compiler-source-import
          .source-input-state: bound-input-state
          admit-current: (lambda () (admit-graph! graph))
          %admission-frame: (and (eq? graph owned-graph) (context-frame graph))))
      (set! owned-graph value)
      (when (and support graph-construction-intact? (object-construction-current?))
        ;; Publish the closed continuation without demanding any package or
        ;; Context input. Later callers only inspect these warm slots.
        (without-observation (lambda () (.ref value '%admission-frame))))
      (set! graph-policy
        (and graph-construction-intact? (object-construction-current?)
             (module-source-object-policy (list value))))
      value)))

;; Cache a runtime binding, never a Graph or an admission result. Only a
;; nonempty runtime support spec demands the existing artifact producer.
(def test-build-projector
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core))
      (eval-syntax '(import (only-in :tao3k/yuanxu/module-system/building/artifacts test-build-projection)))
      (eval-syntax 'test-build-projection))))

;; Discover only the demanded import closure. Never project production entries,
;; evaluate business scopes or scan peer suites to obtain test support.
(def (retained-build-entries specs root package-prefix selected capture: (capture #f) programs?: (programs? #f))
  (unless (and (list? specs) (or (null? specs) (and (string? root) (path-absolute? root))))
    (error "retained build entries require a source root" root))
  (let ((seen (make-hash-table)) (selected-inputs (make-hash-table))
        (language (and (pair? specs) (package-prelude-identity root))))
    ;; Resolve each selected path once. Retained libraries overlap the Module
    ;; projection; a scan per library repeated both POO reads and normalization.
    (for-each
      (lambda (entry)
        (hash-put! selected-inputs (path-normalize (.ref entry 'path)) entry)
        (hash-put! selected-inputs (.ref entry 'compiler-identity) entry))
      selected)
    (map
     (lambda (spec)
       (let* ((make-kind (if (pair? spec) (car spec) 'gxc:))
              (parts (if (string? spec) (list spec)
                        (if (and (pair? spec)
                                 (or (eq? make-kind 'gxc:)
                                     (and programs? (eq? make-kind 'exe:)))) (cdr spec)
                            (error "retained entry must be a Scheme target" spec))))
              (name (and (pair? parts) (car parts)))
              (raw-options (and (pair? parts) (cdr parts)))
              (program? (eq? make-kind 'exe:))
              (explicit-bin? (and program? (pair? raw-options) (eq? (car raw-options) bin:)))
              (bin-name (and program?
                         (if explicit-bin?
                           (and (pair? (cdr raw-options)) (cadr raw-options))
                           (and (string? name) (path-strip-directory name)))))
              (options (if explicit-bin? (and bin-name (cddr raw-options)) raw-options)))
         (unless (and (string? name) (list? options) (andmap string? options)
                      (andmap module-source-name? (string-split name #\/))
                      (not (string-suffix? ".ss" name)))
           (error "invalid retained Scheme target" spec))
         (when (and program? (not (and (string? bin-name) (module-source-name? bin-name))))
           (error "retained program requires a safe bin name" spec))
         ;; Check every unresolved component; normalization must not hide links.
         (def path
           (path-normalize
            (let walk ((directory root) (parts (string-split (string-append name ".ss") #\/)))
             (let (file (path-expand (car parts) directory))
               (unless (eq? (module-source-type file) (if (pair? (cdr parts)) 'directory 'regular))
                 (error "retained source is missing, non-regular or a symlink" file))
               (if (pair? (cdr parts)) (walk file (cdr parts)) file)))))
         (def old (hash-get selected-inputs path))
         (def input (if old (.ref old 'input)
                                 ;; Ordinary retained files own their source/package guards.
                                 ;; The projection checks its selected Graph once at each
                                 ;; independent boundary; do not attach that whole Graph
                                 ;; replay to every file (including every read of its fields).
                                 (yuanxu-prepare-module-retained-source path void capture: capture)))
         (def compiler-identity (.ref input 'compiler-identity))
         ;; Authenticate explicit source identity before expanding its imports.
         ;; An impostor with copied forms must not enter dependency discovery.
         (def selected-input (hash-get selected-inputs compiler-identity))
         (when (and selected-input
                    (not (equal? path (path-normalize (.ref selected-input 'path)))))
           (error "conflicting compiler inputs" compiler-identity))
         (unless (equal? name (build-target-name compiler-identity package-prefix language))
           (error "retained source path and compiler identity disagree" name compiler-identity))
         (when (hash-key? seen compiler-identity)
           (error "duplicate retained compiler target" compiler-identity))
         (hash-put! seen compiler-identity #t)
         (when (and old (not program?) (not (equal? options (.ref old 'options))))
           (error "conflicting retained compiler options" compiler-identity))
         (def kind 'source)
         (def owner 'build)
         (def contributor 'retained)
         ;; Retain the program product even when its source is already selected.
         ;; Returning old here silently changes an executable into a library.
         (if program?
           (.o kind path input options compiler-identity owner contributor make-kind bin-name)
           (or old (.o kind path input options compiler-identity owner contributor))))) specs)))
;; This is compiler-input analysis, not module loading. Read package/prelude
;; metadata and expand the COMPLETE body with Gerbil, including generated and
;; phase-shifted imports. The private context is never installed in the loader,
;; given an evaluator or exposed as a publication capability. Imported modules
;; still go through core-import-module and retain their canonical identities.
(def (test-input-context path)
  (when (member path (current-expander-path))
    (raise-syntax-error #f "Cyclic expansion"
      (append (member path (reverse (current-expander-path))) (list path))))
  (parameterize ((current-expander-context (make-top-context))
                 (current-expander-marks '())
                 (current-expander-phi 0)
                 (current-expander-path (cons path (current-expander-path)))
                 (current-import-expander-phi #f)
                 (current-export-expander-phi #f))
    (let-values (((prelude identity namespace body) (core-read-module path)))
      (def super
        (cond ((prelude-context? prelude) prelude)
              ((module-context? prelude) (core-module->prelude-context prelude))
              ((string? prelude) (core-module->prelude-context (core-import-module prelude)))
              ((not prelude) (or (current-expander-module-prelude) (make-prelude-context #f)))
              (else (error "unsupported runtime module prelude" path prelude))))
      (def context (make-module-context identity super namespace path))
      (core-expand-module-begin body context)
      context)))

(def (module-test-source-spec view demand root entry-source (retained '()))
  ((.ref demand 'admit-current))
  (def entry (yuanxu-prepare-module-retained-source entry-source void))
  (def package-prefix
    (path-strip-trailing-directory-separator
      (path-directory (symbol->string (.ref entry 'compiler-identity)))))
  (def prefix (string-append package-prefix "/"))
  (def files (map path-normalize (.ref demand 'spec)))
  (def prepared (make-hash-table))
  (def observations (.ref entry 'source-inputs))
  (def entries '())
  (def support-contexts '())
  (def compiler-observations (.ref entry 'source-inputs))
  (def compiler-targets (retained-build-entries retained root package-prefix '() programs?: #t))
  (def targets-by-identity (make-hash-table-eq))
  (def static-inputs-api
    (module-binding-action "tao3k/yuanxu/module-system/source/static-inputs" 'module-static-compiler-inputs))
  (def (input! path)
    (def normalized (path-normalize path))
    (def input
      (or (hash-get prepared normalized)
          (let (value (yuanxu-prepare-module-retained-source normalized void))
            (hash-put! prepared normalized value)
            (set! observations (append (.ref value 'source-inputs) observations))
            value)))
    ((.ref input 'admit-current))
    input)
  (for-each
    (lambda (target)
      (def input (input! (.get target path)))
      (hash-put! targets-by-identity (.get target compiler-identity) target)
      (set! compiler-observations
        (append (.ref input 'source-inputs) compiler-observations)))
    compiler-targets)
  (def (std-make-spec entry)
    (def target (hash-get targets-by-identity (car entry)))
    (if target (make-target-spec target (cdr entry)) `(gxc: ,(cdr entry))))
  (def (external-observations path)
    (if (equal? (path-extension path) ".ss")
      (.ref (input! path) 'source-inputs)
      (list (cons path (module-source-read path)))))
  ;; Derive each demanded package from the runtime header/package snapshot.
  ;; External selected owners keep their own identities; no catalog is scanned.
  (def packages (list (cons root package-prefix)))
  (for-each
    (lambda (file)
      (def input (input! file))
      (def metadata
        (find (lambda (row) (and (cdr row) (string=? (path-strip-directory (car row)) "gerbil.pkg")))
          (.ref input 'source-inputs)))
      (when metadata
       (let* ((directory (path-directory (car metadata)))
              (relative (substring file (string-length directory) (- (string-length file) 3)))
              (id (symbol->string (.ref input 'compiler-identity))))
        (unless (string-suffix? relative id)
          (error "test compiler identity has no package-relative source target" file id))
        (def namespace
          (path-strip-trailing-directory-separator
            (substring id 0 (- (string-length id) (string-length relative)))))
        (unless (assoc directory packages)
          (set! packages (cons (cons directory namespace) packages)))))) files)
  (parameterize ((current-expander-context (make-top-context)))
    (def seen (make-hash-table-eq))
    (for-each
      (lambda (file)
        (input! file)
        (for-each-build-module (test-input-context file)
          (lambda (context)
            (def id (expander-context-id context))
            (def name (and (symbol? id) (symbol->string id)))
            (def path (module-context-path context))
            (when (and (string? path) (eq? (module-source-type path) 'regular))
              (let (package
                (and name (find (lambda (entry)
                  (string-prefix? (string-append (cdr entry) "/") name)) packages)))
              (if (and package
                       (equal? (path-normalize path)
                         (path-normalize (path-expand
                           (string-append (build-target-name id (cdr package)) ".ss")
                           (car package)))))
                (let* ((target (build-target-name id (cdr package)))
                       (expected (path-expand (string-append target ".ss") (car package)))
                       (input (input! expected)))
                  (unless (and (equal? (path-normalize path) (path-normalize expected))
                               (eq? id (.ref input 'compiler-identity)))
                    (error "test dependency does not match current package source" id path expected))
                  ;; A Harness input is normally interpreted. If the same
                  ;; owner explicitly declares it as a library, honor that
                  ;; target when it is in this demand's compiler closure.
                  (when (or (hash-key? targets-by-identity id)
                            (not (member (path-normalize expected) files)))
                    ;; std/make resolves BOTH sources and expected products
                    ;; from this projection's root/prefix. A nested gerbil.pkg
                    ;; may identify the source without changing that Make root.
                    ;; Absolute targets discard libdir during path-expand and
                    ;; make valid outputs appear missing on every warm run.
                    (let (make-target (build-target-name id package-prefix))
                      (unless (equal? (path-normalize expected)
                                      (path-normalize
                                        (path-expand (string-append make-target ".ss") root)))
                        (error "test dependency requires its package-owned runtime Make root" id expected root))
                      (set! entries
                        (cons (cons id make-target) entries))
                      (set! support-contexts (cons context support-contexts)))))
                ;; Observe actual external interfaces, never their entire catalog.
                (set! observations (append (external-observations path) observations))))))
          seen)) files))
  ;; Bind products to the compiler closure of the admitted libraries. A Suite
  ;; participates only if it is a declared target or an actual compiler input
  ;; (including for-syntax imports); its role as a Harness input is separate.
  (def programs
    (program-targets (filter (lambda (target) (assq (.get target compiler-identity) entries)) compiler-targets)))
  (def compiler-contexts '())
  (let (seen (make-hash-table-eq))
    (for-each
      (lambda (context)
        (for-each-build-module context
          (lambda (dependency)
            (when (pair? programs) (set! compiler-contexts (cons dependency compiler-contexts)))
            (def path (module-context-path dependency))
            (when (string? path)
              (let (input (hash-get prepared (path-normalize path)))
                (if input
                  (set! compiler-observations
                    (append (.ref input 'source-inputs) compiler-observations))
                  (when (eq? (module-source-type path) 'regular)
                    (set! compiler-observations
                      (append (external-observations path) compiler-observations)))))))
          seen))
      support-contexts))
  (def identities (map car (reverse entries)))
  (def borrowed-static
    (if (pair? programs) (static-inputs-api (list compiler-contexts identities)) '()))
  (def static-guards (map (lambda (input) (.get input admit-current)) borrowed-static))
  (def static-observations (map (lambda (input) (cons (.get input path) (.get input contents))) borrowed-static))
  (def inputs (unique-build-inputs (append static-observations observations)))
  (def compiler-inputs (unique-build-inputs (append static-observations compiler-observations)))
  (def (selected-graph!)
    ;; The init owner supplies a runtime thunk. Merely projecting an empty
    ;; support spec must not evaluate every selected Module declaration.
    (def selected (.ref (if (procedure? view) (view) view) 'selected-graph))
    (unless (eq? selected (.ref demand 'selected-graph))
      (error "test demand belongs to another selected graph"))
    selected)
  (def (current!)
    ;; This source-only guard does not acquire the production build graph.
    ((.ref demand 'admit-current))
    (for-each (lambda (check!) (check!)) static-guards)
    (call-with-module-source-read-cache
      (lambda ()
        (hash-for-each (lambda (_path input) ((.ref input 'admit-current))) prepared)
        (module-source-admit-current! inputs))))
  (current!)
  (def source
    (.o selected-graph: (selected-graph!) demand-source: demand
        compiler-identities: identities source-inputs: compiler-inputs
        program-targets: programs static-inputs: borrowed-static
        source-root: root spec: (map std-make-spec (reverse entries))
        admit-current: current!))
  ;; No products means no compiler/signing authority. Keep the same source and
  ;; selected-Graph guards without importing the artifact implementation.
  (if (null? entries) source
    (let (projection ((force test-build-projector) source))
      ;; Import/initialization is not a pure source-check window.
      (current!)
      projection)))
