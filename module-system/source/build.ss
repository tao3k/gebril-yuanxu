;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Selected Graph/native test demand -> observed compiler inputs. No compilation or execution.
(import (only-in :gerbil/expander current-expander-context make-top-context eval-syntax
                 current-expander-module-import core-import-module syntax-e
                 expander-context-id module-context-path)
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module)
        (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/string/path path-absolute? path-default-extension)
        (only-in :std/list/list find)
        (only-in :gerbil/expander expander-context-id module-context-path)
        (only-in :yuanxu/module-system/building/source-closure package-library-spec)
        (only-in :clan/poo/object .o .cc .ref .get .slot? .all-slots object?)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        (only-in :yuanxu/module-system/source/admission admit-module-value! module-source-type module-source-read module-source-name? module-source-admit-current! call-with-module-source-read-cache module-source-observe current-module-source-phase current-module-source-observer)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source
                 build-target-name yuanxu-prepare-module-retained-source)
        (only-in :yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata)
        (only-in :yuanxu/feature-system/capability-model feature-projection-request?)
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :yuanxu/module-system/building/package write-selected-package))
(export module-test-source-spec module-build-graph unique-build-inputs retained-build-entries BuildContributionContract ExternalPackageContributionContract
        BuildPublicationContract)
(def BuildPublicationContract
  (yuanxu-predicate-contract 'module/build-publication
    (lambda (value)
      (and (object? value) (.slot? value '.restore-build)
           (procedure? (.ref value '.restore-build))))
    (lambda (_v _c) '())))
(def (native-build-root? value)
  (or (and (string? value) (> (string-length value) 0))
      (and (list? value) (>= (length value) 2) (eq? (car value) 'gxc:)
           (string? (cadr value)) (> (string-length (cadr value)) 0)
           (andmap string? (cddr value)))))
(def (build-contribution? value)
  (and (object? value) (.slot? value 'kind) (.slot? value 'roots)
       (eq? (.ref value 'kind) 'module/build)
       (list? (.ref value 'roots)) (andmap native-build-root? (.ref value 'roots))
       (or (not (.slot? value 'library-roots))
           (and (list? (.ref value 'library-roots))
                (andmap string? (.ref value 'library-roots))))))
(def BuildContributionContract
  (yuanxu-predicate-contract 'module/build-contribution build-contribution? (lambda (_v _c) '())))
(def ExternalPackageContributionContract
  (yuanxu-predicate-contract 'module/external-package
    (lambda (value)
      (and (object? value)
           (andmap (cut .slot? value <>) '(kind identity .prepare))
           (eq? (.ref value 'kind) 'module/external-package)
           (symbol? (.ref value 'identity))
           (module-source-name? (symbol->string (.ref value 'identity)))
           (procedure? (.ref value '.prepare))))
    (lambda (_v _c) '())))
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
(def (module-build-graph selected-value prepare-publication)
  (parameterize ((current-module-build-phase? #t))
    (module-build-graph/phase selected-value prepare-publication)))
(def (module-build-graph/phase selected-value prepare-publication)
  (parameterize ((current-module-source-phase 'build-entry))
    ((.ref selected-value 'admit-current)))
  (let ((entry-values '()) (by-path (make-hash-table)) (by-id (make-hash-table))
        (prepared (make-hash-table)) (checks '()) (other '())
        (asset-values '()) (asset-paths (make-hash-table))
        (package-values '()) (package-demands '()) (library-demands '()) (package-refused? #f)
        (package-ids (make-hash-table-eq))
        (cores (make-hash-table-eq)))
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
    (def (add! kind-value input-value options-value owner-id contributor-id)
      (let* ((path-value (if (eq? kind-value 'publication)
                           (.ref (.ref input-value 'source) 'value) (.ref input-value 'path)))
             (id (.ref input-value 'compiler-identity)))
        (cond
         ((hash-key? by-path path-value)
          (let (old (hash-ref by-path path-value))
            (unless (and (eq? kind-value (.ref old 'kind))
                         (equal? options-value (.ref old 'options)))
              (error "conflicting build contributions" path-value (.ref old 'contributor) contributor-id))))
         ((hash-key? by-id id)
          (error "duplicate compiler identity in selected build Graph" id path-value
                 (.ref (hash-ref by-id id) 'path)))
         (else
          (let (entry (.o kind: kind-value path: path-value compiler-identity: id
                          input: input-value options: options-value owner: owner-id contributor: contributor-id))
            (hash-put! by-path path-value entry) (hash-put! by-id id entry)
            (set! checks (cons (.ref input-value 'admit-current) checks))
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
        (add! 'source (or observed-input (yuanxu-prepare-module-build-source path void))
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
          (unless package-root (error "public library entries require native package metadata" owner))
          (let* ((properties (call-with-input-string (cdr metadata) read))
                 (field (and (list? properties) (memq 'package: properties)))
                 (package (and field (pair? (cdr field)) (cadr field)))
                 (entries (.ref projection 'library-roots)))
            (unless (symbol? package) (error "public library entries require a native package identity" owner))
            ;; Confine before expansion, including every unresolved path part.
            (def prefix (string-append (symbol->string package) "/"))
            (for-each
              (lambda (entry)
                (def path (confined-build-path package-root entry))
                (def input (yuanxu-prepare-module-build-source path void))
                (unless (string-prefix? prefix (symbol->string (.ref input 'compiler-identity)))
                  (error "public library entry belongs to another native package" path)))
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
                  ;; Imported leaves inherit an explicitly selected native option
                  ;; set; two explicit contributions still conflict in add!.
                  (add-source! path
                    (if (hash-key? by-path path) (.ref (hash-ref by-path path) 'options) '())
                    owner contributor))))
            (package-library-spec package-root package
              (map (cut path-default-extension <> ".ss") entries) admit-context: admit-context)))))
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
         (let* ((provider (.ref (.ref requirements alias) 'module-id))
                (baseline (hash-ref cores provider)))
           (when (.slot? baseline 'configuration-build)
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
                   (core (.ref (.ref node 'publication) 'core)))
              (when (.slot? core 'build-entries)
                (error "Core build entries are derived from roles; declare only additional projections" owner))
              ;; Preserve the existing compiler order and identity checks. The
              ;; reader has already prepared these roles under its source guard;
              ;; reuse that exact input instead of parsing/retaining it twice.
              (for-each (lambda (path)
                          (add-source! path '() owner contributor
                            (and (.slot? publication 'source-dependencies)
                                 (find (lambda (input)
                                         (equal? (.ref input 'path) path))
                                       (.ref publication 'source-dependencies)))))
                        (.ref publication 'role-sources))
              (when (.slot? publication 'source-dependencies)
                (for-each (lambda (input)
                            (if (and (.slot? input 'kind) (eq? (.ref input 'kind) 'data))
                              (add-asset! input owner)
                              (add! 'source input '() owner contributor)))
                          (.ref publication 'source-dependencies)))
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
    (let ((init-inputs
           ;; Finalization only reads the init source. Share the existing pure
           ;; window for its two Graph checks; close it before any consumer can
           ;; demand external packages, native imports or publication effects.
           (call-with-module-source-read-cache
             (lambda ()
               (current! 'build-finalize)
               (let* ((path (.ref selected-value 'init-source))
                      (inputs (if (and (string? path) (eq? (module-source-type path) 'regular))
                                (list (cons path (module-source-read path))) '())))
                 (current! 'build-finalize)
                 inputs)))))
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
            (current! 'build-admit-after))))))

;; Cache a native binding, never a Graph or an admission result. Only a
;; nonempty native support spec demands the existing artifact producer.
(def test-build-projector
  (delay
    (parameterize ((current-expander-context (make-top-context)))
      (eval-syntax '(import :gerbil/core))
      (eval-syntax '(import (only-in :yuanxu/module-system/building/artifacts test-build-projection)))
      (eval-syntax 'test-build-projection))))

;; Discover only the demanded import closure. Never project production entries,
;; evaluate business scopes or scan peer suites to obtain test support.
(def (retained-build-entries specs root package-prefix selected)
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
                            (error "retained entry must be a native Scheme target" spec))))
              (name (and (pair? parts) (car parts)))
              (options-value (and (pair? parts) (cdr parts))))
         (unless (and (string? name) (list? options-value) (andmap string? options-value)
                      (andmap module-source-name? (string-split name #\/))
                      (not (string-suffix? ".ss" name)))
           (error "invalid retained Scheme target" spec))
         ;; Check every unresolved component; normalization must not hide links.
         (def path-value
           (path-normalize
            (let walk ((directory root) (parts (string-split (string-append name ".ss") #\/)))
             (let (file (path-expand (car parts) directory))
               (unless (eq? (module-source-type file) (if (pair? (cdr parts)) 'directory 'regular))
                 (error "retained source is missing, non-regular or a symlink" file))
               (if (pair? (cdr parts)) (walk file (cdr parts)) file)))))
         (def old (hash-get selected-by-path path-value))
         (def prepared-input (if old (.ref old 'input)
                                 ;; Ordinary retained files own their source/package guards.
                                 ;; The projection checks its selected Graph once at each
                                 ;; independent boundary; do not attach that whole Graph
                                 ;; replay to every file (including every read of its fields).
                                 (yuanxu-prepare-module-retained-source path-value void)))
         (def identity (.ref prepared-input 'compiler-identity))
         (unless (equal? name (build-target-name identity package-prefix))
           (error "retained source path and compiler identity disagree" name identity))
         (when (hash-key? seen identity)
           (error "duplicate retained compiler target" identity))
         (hash-put! seen identity #t)
         (when (and old (not (equal? options-value (.ref old 'options))))
           (error "conflicting retained compiler options" identity))
         (or old (.o kind: 'source path: path-value input: prepared-input options: options-value
                     compiler-identity: identity owner: 'build contributor: 'retained)))) specs)))
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
  (def native-targets (retained-build-entries retained root package-prefix '()))
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
    native-targets)
  (def (native-spec entry)
    (def target (find (lambda (candidate) (eq? (.get candidate compiler-identity) (car entry))) native-targets))
    `(gxc: ,(cdr entry) ,@(if target (.get target options) '())))
  ;; Derive each demanded package from the native header/package snapshot.
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
  (def native-import (current-expander-module-import))
  (def (source-import path (reload? #f))
    (def datum (syntax-e path))
    (def name (and (symbol? datum) (symbol->string datum)))
    (def local
      (or
        (and name
          (ormap
            (lambda (package)
              (def prefix (string-append ":" (cdr package) "/"))
              (and (string-prefix? prefix name)
                (path-expand (string-append (substring name (string-length prefix)
                  (string-length name)) ".ss") (car package)))) packages))
        (and (equal? package-prefix "yuanxu") (eq? datum ':tao3k/yuanxu/prelude)
          (path-expand "prelude.ss" root))
        (and (string? datum) (path-absolute? datum) (string=? (path-extension datum) ".ss")
          (ormap (lambda (package) (string-prefix? (car package) datum)) packages) datum)))
    (cond
     ;; A compiled library owns its native import closure. Rewriting imports
     ;; inside its interface made discovery depend on which SDK modules had
     ;; already been loaded, and rebuilt library sources as test support.
     ((and (string? datum) (string=? (path-extension datum) ".ssi"))
      (parameterize ((current-expander-module-import native-import))
        (native-import path reload?)))
     ((and local (module-source-type local))
      (begin
        (when reload? (error "test imports require a fresh source epoch" local))
        (let* ((input (input! local)) (context (native-import local #f)))
          ((.ref input 'admit-current))
          context)))
     (else (native-import path reload?))))
  (parameterize ((current-expander-context (make-top-context))
                 (current-expander-module-import source-import))
    (def seen (make-hash-table-eq))
    (for-each
      (lambda (file)
        (input! file)
        (for-each-build-module (core-import-module file)
          (lambda (context)
            (def id (expander-context-id context))
            (def name (and (symbol? id) (symbol->string id)))
            (def path (module-context-path context))
            (when (and (string? path) (eq? (module-source-type path) 'regular))
              (let (package
                (and name (find (lambda (entry)
                  (or (string-prefix? (string-append (cdr entry) "/") name)
                      (and (equal? (cdr entry) "yuanxu") (eq? id 'tao3k/yuanxu/prelude)))) packages)))
              (if (and package (string=? (path-extension path) ".ss"))
                (let* ((target (build-target-name id (cdr package)))
                       (expected (path-expand (string-append target ".ss") (car package)))
                       (input (input! expected)))
                  (unless (and (equal? (path-normalize path) (path-normalize expected))
                               (eq? id (.ref input 'compiler-identity)))
                    (error "test dependency does not match current package source" id path expected))
                  (unless (member (path-normalize expected) files)
                    ;; Native Make resolves BOTH sources and expected products
                    ;; from this projection's root/prefix. A nested gerbil.pkg
                    ;; may identify the source without changing that Make root.
                    ;; Absolute targets discard libdir during path-expand and
                    ;; make valid outputs appear missing on every warm run.
                    (let (make-target (build-target-name id package-prefix))
                      (unless (equal? (path-normalize expected)
                                      (path-normalize
                                        (path-expand (string-append make-target ".ss") root)))
                        (error "test dependency requires its package-owned native Make root" id expected root))
                      (set! entries
                        (cons (cons id make-target) entries))
                      (set! support-contexts (cons context support-contexts)))))
                ;; Observe actual external interfaces, never their entire catalog.
                (when (member (path-extension path) '(".ss" ".ssi"))
                  (set! observations (cons (cons path (module-source-read path)) observations)))))))
          seen)) files))
  ;; A Suite is interpreted by the harness, not compiled into its support
  ;; library. Bind products to the actual compiler dependency closure instead
  ;; of the requesting Suite's bytes. Walk native contexts, rather than simply
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
                  (when (member (path-extension path) '(".ss" ".ssi"))
                    (set! compiler-observations
                      (cons (cons path (module-source-read path)) compiler-observations)))))))
          seen))
      support-contexts))
  (def inputs (unique-build-inputs observations))
  (def compiler-inputs (unique-build-inputs compiler-observations))
  (def (selected-graph!)
    ;; The init owner supplies a native thunk. Merely projecting an empty
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
        source-root: root spec: (map native-spec (reverse entries))
        admit-current: current!))
  ;; No products means no compiler/signing authority. Keep the same source and
  ;; selected-Graph guards without importing the artifact implementation.
  (if (null? entries) source
    (let (projection ((force test-build-projector) source))
      ;; Import/initialization is not a pure source-check window.
      (current!)
      projection)))
