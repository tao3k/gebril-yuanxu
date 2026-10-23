;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Selected Graph -> admitted compiler inputs. No resolver, compiler or executor.
(import (only-in :std/crypto/digest sha256)
        (only-in :std/encoding/hex hex-encode)
        (only-in :std/string/path path-absolute? path-default-extension)
        (only-in :std/list/list find)
        (only-in :clan/poo/object .o .cc .ref .slot? .all-slots object?)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        (only-in :yuanxu/module-system/source/admission admit-module-value! module-source-type module-source-read module-source-name? call-with-module-source-read-cache module-source-observe current-module-source-phase current-module-source-observer)
        (only-in :yuanxu/module-system/source/preparation yuanxu-prepare-module-build-source)
        (only-in :yuanxu/module-system/source/objects yuanxu-module-source-ref-metadata)
        (only-in :yuanxu/feature-system/capability-model feature-projection-request?)
        (only-in :yuanxu/module-system/source/declaration current-module-build-phase?)
        (only-in :yuanxu/module-system/building/package write-selected-package))
(export module-build-graph unique-build-inputs BuildContributionContract ExternalPackageContributionContract
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
       (list? (.ref value 'roots)) (andmap native-build-root? (.ref value 'roots))))
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
        (package-values '()) (package-demands '()) (package-refused? #f)
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
              (.ref projection 'roots))))
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
