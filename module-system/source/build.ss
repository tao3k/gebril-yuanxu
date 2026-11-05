;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Selected Graph/runtime test demand -> observed compiler inputs. No compilation or execution.
(import (only-in :gerbil/expander current-expander-context make-top-context eval-syntax
                 core-import-module __module-registry expander-context-id module-context-path
                 core-read-module core-expand-module-begin make-module-context
                 core-module->prelude-context module-context? prelude-context?
                 make-prelude-context current-expander-module-prelude
                 current-expander-path current-expander-marks current-expander-phi
                 current-import-expander-phi current-export-expander-phi raise-syntax-error)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module package-library-spec/source-context)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/string/path path-absolute? path-default-extension)
        (only-in :std/list/list find foldl)
        (only-in :clan/poo/slot-observation without-observation)
        (only-in :clan/poo/read-route require-read-route!)
        (only-in :yuanxu/object-family/read-projection owned-read-function-scope?)
        (runtime: :clan/poo/object)
        (only-in :clan/poo/mop define-type Type.)
        (only-in :clan/poo/type List)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :yuanxu/module-system/source/admission admit-module-value! module-source-type module-source-read module-source-name? module-source-admit-current! call-with-module-source-read-cache module-source-observe module-source-object-policy current-module-source-phase current-module-source-observer module-source-measure-operation call-with-module-source-callback)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source
                 build-target-name yuanxu-prepare-module-retained-source module-compiler-source-owner?)
        (only-in :yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata)
        (only-in :yuanxu/module-system/source/publication requirement-option)
        (only-in :yuanxu/feature-system/capability-model feature-projection-request?)
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :yuanxu/module-system/building/package write-selected-package))
(export module-test-source-spec module-build-graph unique-build-inputs retained-build-entries BuildContributionContract ExternalPackageContributionContract BuildSpecContract
        BuildPublicationContract)
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
(define-type (BuildTargetContract @ Type.)
  identity: 'module/build-target .element?: build-root?)
;; Pure native-spec shape and composition. Source/publication authentication
;; remains in the enclosing init-owned boundary, never in a claimed origin tag.
(def BuildSpecContract
  (.cc ObjectContract. identity: 'module/build-spec
    responsibilities:
    (.o module-spec: (List BuildTargetContract)
        library-spec: (List BuildTargetContract)
        spec: (List BuildTargetContract))
    obligations:
    (lambda (candidate location)
      (if (equal? (.ref candidate 'spec)
                  (append (.ref candidate 'module-spec) (.ref candidate 'library-spec)))
        '()
        (list (.o kind: 'build-spec-merge-mismatch path: (append location '(spec))))))))
(def (build-contribution? value)
  (and (object? value) (.slot? value 'kind) (.slot? value 'roots)
       (eq? (.ref value 'kind) 'module/build)
       (list? (.ref value 'roots)) (andmap build-root? (.ref value 'roots))
       (or (not (.slot? value 'library-roots))
           (and (list? (.ref value 'library-roots))
                (andmap string? (.ref value 'library-roots))))))
(define-type (BuildContributionContract @ Type.)
  identity: 'module/build-contribution .element?: build-contribution?)
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
(def (module-build-graph selected-value prepare-publication (source-window #f) (source-state #f))
  (parameterize ((current-module-build-phase? #t))
    (module-build-graph/phase selected-value prepare-publication source-window source-state)))
(def (module-build-graph/phase selected-value prepare-publication source-window source-state)
  (parameterize ((current-module-source-phase 'build-entry))
    ((.ref selected-value 'admit-current)))
  (let ((entry-values '()) (by-path (make-hash-table)) (by-id (make-hash-table-eq))
        (prepared (make-hash-table)) (checks '()) (other '())
        (asset-values '()) (asset-paths (make-hash-table))
        (package-values '()) (package-demands '()) (library-demands '()) (package-refused? #f)
        (package-ids (make-hash-table-eq))
        (cores (make-hash-table-eq)) (owned-graph #f) (graph-policy #f) (entry-construction-intact? (object-construction-current?)))
    ;; Index the already-selected Core nodes once; dependency edges select
    ;; configuration builders, never a second directory/provider scan.
    (for-each (lambda (node)
                (when (eq? (.ref node 'kind) 'module-core)
                  (hash-put! cores (.ref node 'owner) (.ref (.ref node 'publication) 'core))))
              (.ref selected-value 'nodes))
    (def (check-current! observed-checks)
      ((.ref selected-value 'admit-current))
      (for-each (lambda (check) (check)) observed-checks))
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
          (set! checks (cons (.ref value 'admit-current) checks)) value)))
    (def (add! kind input options owner contributor)
      (let* ((path (if (eq? kind 'publication)
                      (.ref (.ref input 'source) 'value) (.ref input 'path)))
             (compiler-identity (.ref input 'compiler-identity)))
        (cond
         ((hash-key? by-path path)
          (let (old (hash-ref by-path path))
            (unless (and (eq? kind (.ref old 'kind))
                         (equal? options (.ref old 'options)))
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
            (set! checks (cons (.ref input 'admit-current) checks))
            (set! entry-values (cons entry entry-values)))))))
    (def (add-asset! input-value owner-id)
      (def file (.ref input-value 'path))
      (when (hash-key? asset-paths file)
        (error "duplicate selected configuration asset" file owner-id))
      (hash-put! asset-paths file #t)
      (set! checks (cons (.ref input-value 'admit-current) checks))
      (set! asset-values (cons (.cc input-value owner: owner-id) asset-values)))
    ;; current! validates the selected context once before these local guards.
    ;; Capturing it again per entry makes each check recursively rewalk all Modules.
    ;; Local guards still re-read bytes/package identity on every boundary.
    (def (add-source! path options-value owner contributor (observed-input #f))
      (if (hash-key? by-path path)
        (add! 'source (.ref (hash-ref by-path path) 'input) options-value owner contributor)
        (add! 'source
          (or observed-input
            (yuanxu-prepare-module-build-source path void
              capture: (lambda (value checker path ready? state)
                         (when state (hash-put! by-id value state)) value)))
          options-value owner contributor)))
    ;; Package public entries belong to their declaring Module. Gerbil supplies
    ;; the actual import graph; the existing preparer guards every local source.
    ;; Owner-relative roots remain confined and keep their explicit options.
    (def (add-library! publication projection owner contributor)
      (when (and (.slot? projection 'library-roots)
                 (pair? (.ref projection 'library-roots)))
        (let* ((metadata (find (lambda (row)
                                (and (cdr row) (string=? (path-strip-directory (car row)) "gerbil.pkg")))
                              (.ref publication 'source-inputs)))
               (package-root (and metadata (path-normalize (path-directory (car metadata))))))
          (unless package-root (error "public library entries require runtime package metadata" owner))
          (let* ((properties (call-with-input-string (cdr metadata) read))
                 (field (and (list? properties) (memq 'package: properties)))
                 (package (and field (pair? (cdr field)) (cadr field)))
                 (entries (.ref projection 'library-roots)))
            (unless (symbol? package) (error "public library entries require a runtime package identity" owner))
            ;; Confine before expansion, including every unresolved path part.
            (def prefix (string-append (symbol->string package) "/"))
            (for-each
              (lambda (entry)
                (def path (confined-build-path package-root entry))
                (def input (yuanxu-prepare-module-build-source path void))
                (unless (string-prefix? prefix (symbol->string (.ref input 'compiler-identity)))
                  (error "public library entry belongs to another runtime package" path)))
              entries)
            (def (admit-context context)
              (def identity (expander-context-id context))
              (when (and (symbol? identity) (string-prefix? prefix (symbol->string identity)))
                (let* ((relative (substring (symbol->string identity) (string-length prefix)
                                            (string-length (symbol->string identity))))
                       (path (confined-build-path package-root relative))
                       (actual (module-context-path context)))
                  (unless (and (string? actual) (equal? path (path-normalize actual)))
                    (error "public library compiler source differs from declared package" identity path actual))
                  ;; Imported leaves inherit an explicitly selected runtime option
                  ;; set; two explicit contributions still conflict in add!.
                  (add-source! path
                    (if (hash-key? by-path path) (.ref (hash-ref by-path path) 'options) '())
                    owner contributor))))
            (def (declared-source-context context)
              (let ((identity (expander-context-id context))
                    (actual (module-context-path context)))
                (if (and (symbol? identity) (string? actual)
                         (string=? (path-extension actual) ".ssi")
                         (string-prefix? prefix (symbol->string identity)))
                  ;; A compiled dependency may be this consumer's hot product.
                  ;; Expand the confined source before traversing its imports.
                  (let* ((relative (substring (symbol->string identity) (string-length prefix)
                                             (string-length (symbol->string identity))))
                         (path (confined-build-path package-root relative))
                         (source (core-import-module path)))
                    (unless (eq? identity (expander-context-id source))
                      (error "public library compiler identity differs from declared package" identity path))
                    source)
                  context)))
            (package-library-spec/source-context package-root package
              (map (cut path-default-extension <> ".ss") entries)
              admit-context declared-source-context)))))
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
          (set! package-values
            (cons (if provider
                    (.cc request 'identity key 'package-identity id
                         'build-owner provider 'configuration-owner owner 'dependency-alias contributor)
                    (.cc request 'scope-owner owner))
                  package-values)))))
    (def (add-configuration-builds! owner requirements)
      (for-each
       (lambda (alias)
         (let* ((requirement (.ref requirements alias))
                (provider (.ref requirement 'module-id))
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
          ((and (object? projection) (.slot? projection 'kind)
                (eq? (.ref projection 'kind) 'module/build))
           (admit-module-value! BuildContributionContract projection selected-value)
           (let* ((publication (owner-preparation owner))
                  (metadata (yuanxu-module-source-ref-metadata (.ref publication 'source)))
                  (root (or (assq 'module-root metadata) (assq 'module-tree-root metadata))))
             (unless root (error "build contribution has no admitted source root" owner))
             (for-each
              (lambda (spec)
                (add-source! (confined-build-path (cdr root) (if (string? spec) spec (cadr spec)))
                             (if (string? spec) '() (cddr spec)) owner contributor-value))
              (.ref projection 'roots))
             (set! library-demands
               (cons (list publication projection owner contributor-value) library-demands))))
          ((feature-projection-request? projection)
           ;; A build request still needs an admitted concrete build contribution.
           (when (eq? (.ref projection 'projection-id) 'build)
             (error "unresolved build projection request" contributor-value projection))
           (set! other (cons (.o contributor: contributor-value request: projection) other)))
          (else (error "unknown or malformed selected projection" contributor-value projection)))) projections))
    (for-each
     (lambda (node)
       (let ((owner (.ref node 'owner)) (contributor (.ref node 'identity)))
         (case (.ref node 'kind)
           ((module-core)
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
                          (add-source! path '() owner contributor
                            (and inputs
                                 (find (lambda (input)
                                         (equal? (.ref input 'path) path))
                                       inputs))))
                        (.ref publication 'role-sources))
              (when inputs
                (for-each (lambda (input)
                            (if (and (.slot? input 'kind) (eq? (.ref input 'kind) 'data))
                              (add-asset! input owner)
                              (add! 'source input '() owner contributor)))
                          inputs))
              (add! 'publication publication '() owner contributor)
              (when (.slot? core 'projections)
                (add-projections! owner contributor (.ref core 'projections)))
              (add-configuration-builds! owner (.ref core 'requires))))
           ((feature)
            (add-projections! owner contributor (.ref (.ref node 'descriptor) 'projections)))
           (else (error "unknown selected Graph node" node))))) (.ref selected-value 'nodes))
    ;; All explicit selected contributions decide options before a public import
    ;; closure inherits them. Module order cannot manufacture an option conflict.
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
          admit-current:
          (lambda ()
            (current! 'build-admit-before)
            ;; Observe the actual getter/callback boundary, not a reconstructed
            ;; request tree. Position is diagnostic only; do not read identity
            ;; slots here and contaminate a surrounding admission's MOP reads.
            (let loop ((requests external-packages) (position 0))
              (unless (null? requests)
                (let ((observer (current-module-source-observer))
                      (name (list 'build-request position)))
                  (if observer
                    (dynamic-wind
                      (lambda () (observer (list 'admission-stage-start name) 1))
                      (lambda () ((.ref (car requests) 'admit-current)))
                      (lambda () (observer (list 'admission-stage-end name) 1)))
                    ((.ref (car requests) 'admit-current))))
                (loop (cdr requests) (+ position 1))))
            (current! 'build-admit-after))))
      (set! owned-graph value)
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
      (eval-syntax '(import (only-in :yuanxu/module-system/building/artifacts test-build-projection)))
      (eval-syntax 'test-build-projection))))

;; Discover only the demanded import closure. Never project production entries,
;; evaluate business scopes or scan peer suites to obtain test support.
(def (retained-build-entries specs root package-prefix selected capture: (capture #f))
  (unless (and (list? specs) (or (null? specs) (and (string? root) (path-absolute? root))))
    (error "retained build entries require a source root" root))
  (let ((seen (make-hash-table-eq)) (selected-by-path (make-hash-table)))
    ;; Resolve each selected path once. Retained libraries overlap the Module
    ;; projection; a scan per library repeated both POO reads and normalization.
    (for-each
      (lambda (entry)
        (hash-put! selected-by-path (path-normalize (.ref entry 'path)) entry))
      selected)
    (map
     (lambda (spec)
       (let* ((parts (if (string? spec) (list spec)
                        (if (and (pair? spec) (eq? (car spec) 'gxc:)) (cdr spec)
                            (error "retained entry must be a Scheme target" spec))))
              (name (and (pair? parts) (car parts)))
              (options (and (pair? parts) (cdr parts))))
         (unless (and (string? name) (list? options) (andmap string? options)
                      (andmap module-source-name? (string-split name #\/))
                      (not (string-suffix? ".ss" name)))
           (error "invalid retained Scheme target" spec))
         ;; Check every unresolved component; normalization must not hide links.
         (def path
           (path-normalize
            (let walk ((directory root) (parts (string-split (string-append name ".ss") #\/)))
             (let (file (path-expand (car parts) directory))
               (unless (eq? (module-source-type file) (if (pair? (cdr parts)) 'directory 'regular))
                 (error "retained source is missing, non-regular or a symlink" file))
               (if (pair? (cdr parts)) (walk file (cdr parts)) file)))))
         (def old (hash-get selected-by-path path))
         (def input (if old (.ref old 'input)
                                 ;; Ordinary retained files own their source/package guards.
                                 ;; The projection checks its selected Graph once at each
                                 ;; independent boundary; do not attach that whole Graph
                                 ;; replay to every file (including every read of its fields).
                                 (yuanxu-prepare-module-retained-source path void capture: capture)))
         (def compiler-identity (.ref input 'compiler-identity))
         (unless (equal? name (build-target-name compiler-identity package-prefix))
           (error "retained source path and compiler identity disagree" name compiler-identity))
         (when (hash-key? seen compiler-identity)
           (error "duplicate retained compiler target" compiler-identity))
         (hash-put! seen compiler-identity #t)
         (when (and old (not (equal? options (.ref old 'options))))
           (error "conflicting retained compiler options" compiler-identity))
         (def kind 'source)
         (def owner 'build)
         (def contributor 'retained)
         (or old (.o kind path input options compiler-identity owner contributor)))) specs)))
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
  (def compiler-targets (retained-build-entries retained root package-prefix '()))
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
      (set! compiler-observations
        (append (.ref input 'source-inputs) compiler-observations)))
    compiler-targets)
  (def (std-make-spec entry)
    (def target (find (lambda (candidate) (eq? (.get candidate compiler-identity) (car entry))) compiler-targets))
    `(gxc: ,(cdr entry) ,@(if target (.get target options) '())))
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
                  (unless (member (path-normalize expected) files)
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
                (set! observations (cons (cons path (module-source-read path)) observations))))))
          seen)) files))
  ;; A Suite is interpreted by the harness, not compiled into its support
  ;; library. Bind products to the actual compiler dependency closure instead
  ;; of the requesting Suite's bytes. Walk runtime contexts, rather than simply
  ;; removing Suite paths: a Suite imported by support (including for-syntax)
  ;; IS a compiler input and must still invalidate those products.
  (let (seen (make-hash-table-eq))
    (for-each
      (lambda (context)
        (for-each-build-module context
          (lambda (dependency)
            (def path (module-context-path dependency))
            (when (string? path)
              (let (input (hash-get prepared (path-normalize path)))
                (if input
                  (set! compiler-observations
                    (append (.ref input 'source-inputs) compiler-observations))
                  (when (eq? (module-source-type path) 'regular)
                    (set! compiler-observations
                      (cons (cons path (module-source-read path)) compiler-observations)))))))
          seen))
      support-contexts))
  (def inputs (unique-build-inputs observations))
  (def compiler-inputs (unique-build-inputs compiler-observations))
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
    (call-with-module-source-read-cache
      (lambda ()
        (hash-for-each (lambda (_path input) ((.ref input 'admit-current))) prepared)
        (module-source-admit-current! inputs))))
  (current!)
  (def source
    (.o selected-graph: (selected-graph!) demand-source: demand
        compiler-identities: (map car (reverse entries)) source-inputs: compiler-inputs
        source-root: root spec: (map std-make-spec (reverse entries))
        admit-current: current!))
  ;; No products means no compiler/signing authority. Keep the same source and
  ;; selected-Graph guards without importing the artifact implementation.
  (if (null? entries) source
    (let (projection ((force test-build-projector) source))
      ;; Import/initialization is not a pure source-check window.
      (current!)
      projection)))
