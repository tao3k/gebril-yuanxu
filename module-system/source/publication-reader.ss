;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Read one publication through its confined native imports and delayed roles.
(import (only-in :std/list/list find)
        (only-in :yuanxu/configuration/json current-configuration-input-observer)
        (only-in :yuanxu/ops/progress execution-progress!)
        (only-in :std/io/tempfile make-temporary-file-name)
        (only-in :gerbil/expander current-expander-context make-top-context
                 current-expander-module-import eval-syntax eval-module expander-context-id module-context-path
                 core-library-package-path-prefix module-context-code module-context?
                 current-expander-compile current-expander-eval expander-context-table syntax-e)
        (only-in :clan/poo/object .o .ref .slot?)
        :yuanxu/module-system/source/admission
        :yuanxu/module-system/source/preparation
        (only-in :yuanxu/module-system/source/declaration current-module-build-resolver)
        (only-in :yuanxu/module-system/source/deferred-declaration
                 current-module-role-resolver module-role-values)
        :yuanxu/module-system/source/objects
        (only-in :yuanxu/module-system/building/source-closure for-each-build-module
                 yuanxu-library-identity?)
        (only-in :yuanxu/module-system/building/source-package module-build-source-path))
(import :yuanxu/module-system/source/reader-support
        :yuanxu/module-system/source/reader-evaluation
        :yuanxu/module-system/source/compiler-tools
        :yuanxu/module-system/source/configuration-reader
        :yuanxu/module-system/source/reader-session
        :yuanxu/module-system/source/reader-preparation
        :yuanxu/module-system/source/reader-guards)
(export reader-read-publication)

(def (reader-read-publication session source-value (source-prefix #f) (consume #f) (discovered #f))
  (with-catch
   (lambda (exception) (set! (reader-session-refused? session) #t) (raise exception))
   (lambda ()
     (def located? (and source-prefix #t))
     ;; The runtime directory linker supplies this PRIVATE closed prefix:
     ;; its metadata guard followed by inert init/directory location.
     ;; Share the existing pure observation window with our FULL entry guard,
     ;; then END it before policy admission, macros or initialization.
     ;; No check/bytes survive into the publication body or its caller.
     (when located?
       (set! source-value
         (call-with-module-source-read-cache
           (lambda ()
             (let (source (source-prefix))
               (parameterize ((current-module-source-phase 'declaration-before)) (reader-current! session))
               source))))
       ;; Deferred Build resolvers share this lexical frame. The consumed
       ;; private caller continuation is not part of their source support.
       (set! source-prefix #f))
     (when (current-module-source-observer)
       ((current-module-source-observer)
         (list 'publication-start (yuanxu-module-source-ref-value source-value)) 1))
     (unless located?
       (parameterize ((current-module-source-phase 'declaration-before)) (reader-current! session)))
     (let* ((prepared (or discovered (reader-prepare-publication session source-value)))
            (interface-path (path-normalize (yuanxu-module-source-ref-value source-value)))
            (root (path-directory interface-path))
            (tree-row (assq 'collection-root (yuanxu-module-source-ref-metadata source-value)))
            (tree (and tree-row (path-normalize (cdr tree-row))))
            (source-tree-row (assq 'source-tree (yuanxu-module-source-ref-metadata source-value)))
            (source-tree (and source-tree-row (cdr source-tree-row)))
            (package-input (find (lambda (row) (and (cdr row) (string=? (path-strip-directory (car row)) "gerbil.pkg")))
                                 (.ref prepared 'source-inputs)))
            (package-root (and package-input (path-normalize (path-directory (car package-input)))))
            ;; Source authority comes from the owning directory Context,
            ;; independently of a nested compiler package/prelude boundary.
            (repository-root
              (let (origin (assq 'kernel-root (yuanxu-module-source-ref-metadata source-value)))
                (and origin (cdr origin))))
            ;; Compiler package metadata does not grant source authority.
            ;; A directory window carries its declared origin explicitly;
            ;; a bare SourceRef grants only its own Module's source scope.
            (kernel-root repository-root)
            (kernel-depth 0)
            (directory (make-temporary-file-name "publication-reader-"))
            (prefix (symbol->string (gensym 'publication-reader-)))
            (wrappers (make-hash-table)) (artifacts (make-hash-table))
            (completed (make-hash-table-eq))
            (input-values '()) (input-paths (make-hash-table)) (gerbil-import (current-expander-module-import)))
       (defvalues (compile evaluate)
         (reader-evaluation-observers artifacts completed
           (lambda (context action)
             (call-with-collected-module-sources
               (lambda (sources-current!)
                 (call-with-publication-reads action
                   (lambda (results reads-current! _roots)
                     (hash-put! (reader-session-kernel-initializers session) context
                       (lambda () (reads-current!) (sources-current!)))
                     results)))))))
       (def (write-wrapper path forms runtime-identity)
         (let* ((name (string-append (number->string (hash-length wrappers)) "-" (path-strip-directory path)))
                (target (path-expand name directory)))
           (call-with-output-file target
             (lambda (port)
               ;; Preserve runtime relative-symbol import resolution. Only the
               ;; private namespace/filename changes, not its package parent.
               (write 'package: port) (display " " port)
               (write (path-strip-trailing-directory-separator
                        (path-directory (symbol->string runtime-identity))) port)
               (newline port)
               (write 'namespace: port) (display " " port)
               (write (string-append prefix "/" (path-strip-extension name)) port) (newline port)
               (for-each (lambda (form) (write form port) (newline port)) forms)))
           (hash-put! artifacts (path-normalize target) #t)
           (hash-put! wrappers path target) target))
       (def (record-input! input)
         (let (path (.ref input 'path))
           (unless (hash-key? input-paths path)
             ;; The existing uniqueness index owns the input itself.
             ;; Runtime imports recurse before returning: a role need not
             ;; remain the head of input-values when its context arrives.
             (hash-put! input-paths path input)
             (reader-enroll-candidate! session (.ref input 'admit-current))
             (set! input-values (cons input input-values)))))
       (def (record-data! file text)
         (def relative
           (let (prefix (string-append (path-strip-trailing-directory-separator root) "/"))
             (unless (string-prefix? prefix file)
               (error "configuration asset leaves its Module" file root))
             (substring file (string-length prefix) (string-length file))))
         ;; No escaping directory symlinks, even when the final file is regular.
         (let walk ((directory root) (parts (string-split relative #\/)))
           (let (next (path-expand (car parts) directory))
             (unless (eq? (module-source-type next) (if (pair? (cdr parts)) 'directory 'regular))
               (error "configuration asset must be owner-confined and regular" file))
             (when (pair? (cdr parts)) (walk next (cdr parts)))))
         (def observations (list (cons file (string-copy text))))
         (def (asset-current!)
           (module-source-admit-current! observations "selected configuration asset changed"))
         (asset-current!)
         (unless (hash-key? input-paths file)
           (set! (reader-session-guards session)
             (cons (make-source-preparation #f asset-current! #f file asset-current! #f (lambda () #t)) (reader-session-guards session)))
           (record-input!
             (.o kind: 'data path: file relative-path: relative
                 source-inputs: observations admit-current: asset-current!))))
       (def (within? directory path)
         (string-prefix? (string-append (path-strip-trailing-directory-separator directory) "/") path))
       (def (tool-context context reload?)
         (when reload? (error "compiler tool reload requires a fresh publication reader"))
         (let (expected (hash-get (reader-session-tool-contexts session) (expander-context-id context)))
           (unless (captured-tool-context? (reader-session-compiler-contexts session) context)
             ;; Preserve the strict runtime identity check and report both
             ;; origins so source/compiled aliases can be diagnosed.
             (error "compiler tool context changed during publication"
               (expander-context-id context)
               (and (module-context? context) (module-context-path context))
               (and (module-context? expected) (module-context-path expected)))))
         ;; This walk is a pure source check, not expansion. Shared tool
         ;; ancestors must not reread the same bytes once per import edge.
         ;; End the observation scope before returning to gerbil-import.
         (def (visit-tool-input input execution?)
               ;; The explicit Gerbil bootstrap includes shared JSON artifact
               ;; definitions beside the JSON Module. Directory ownership
               ;; alone does not make those canonical libraries a role.
               ;; Actual publication roles (including deferred Build) must
               ;; never become implicit compiler capabilities.
               (def path (path-normalize (.ref input 'path)))
               (when (or (equal? path interface-path)
                         (member path (.ref prepared 'role-sources))
                         (equal? path (.ref prepared 'build-source)))
                 (error "compiler tool cannot depend on Module implementation" path))
               (when (and execution? ((reader-session-candidate session)))
                 (record-source-observations! (candidate-support-tools ((reader-session-candidate session)))
                   (.ref input 'source-inputs)))
               ;; Gerbil tool sources remain guarded in tool-observations.
               ;; Only this repository's sources become compiler entries;
               ;; a contribution must not rebuild its installed Core libraries.
               (when (and kernel-root
                          (within? kernel-root path)
                          ;; A linked Gerbil can be nested in a consumer's
                          ;; .data tree. Filesystem containment does not
                          ;; transfer its runtime compiler package ownership.
                          (let (prefix (core-library-package-path-prefix kernel-root))
                            (and prefix
                                 (string-prefix? prefix
                                   (symbol->string (.ref input 'compiler-identity))))))
                 (record-input! input)
                 ;; An explicit owner may be a different checkout from this
                 ;; interpreter's compile anchor. Bind its verified input to
                 ;; the SAME captured native Context, never re-evaluate tools
                 ;; merely because their source spelling changed. The private
                 ;; preparation association, not a matching name, is authority.
                 (let* ((native (hash-get (reader-session-tool-contexts session) (.ref input 'compiler-identity)))
                        (previous (hash-get (reader-session-tool-paths session) path)))
                   (unless (and native (captured-tool-context? (reader-session-compiler-contexts session) native)
                                (eq? input (compiler-tool-input native path)))
                     (error "owned compiler source has competing native contexts" path))
                   (when (and previous (not (eq? previous native)))
                     (error "owned compiler source has competing native aliases" path))
                   (hash-put! (reader-session-tool-paths session) path native))))
         (parameterize ((current-module-source-phase 'compiler-import))
           (call-with-module-source-read-cache
            (lambda ()
             (admit-compiler-inputs! context (reader-session-tool-dependencies session)
               (lambda (input) (visit-tool-input input #t)))
             (when kernel-root
               (for-each (lambda (input) (visit-tool-input input #f))
                 ((reader-session-tool-dependencies session) context kernel-root))))))
         context)
       (def (source-wrapper original-path allowed-root)
         (let (path (path-normalize original-path))
           (when (equal? path interface-path)
             (error "publication bootstrap cannot import its own interface" interface-path))
           (or (hash-get wrappers path)
               (let (input (module-source-measure-operation 'reader-private-prepare
                              (lambda () (yuanxu-prepare-module-private-source allowed-root original-path void
                                           capture: (cut reader-capture-input session <...>)))))
                 (reader-add-input-guard! session input)
                 (record-input! input)
                 (write-wrapper path (reader-body (.ref input 'compiler-forms)) (.ref input 'compiler-identity))))))
       (def (shared-context original-path owner-root reload? (shared? #t))
         (let* ((path (path-normalize original-path))
                (retained
                 (or (hash-get (reader-session-kernel-contexts session) path)
                     (and (reader-session-previous-context session) source-tree (not reload?)
                       ((reader-session-previous-context session) path
                         (lambda (input-path)
                           (let (owner ((.ref source-tree 'locate-owner) input-path))
                             (if owner (list (.ref owner 'identity) (.ref owner 'root))
                               (and kernel-root (within? kernel-root input-path)
                                    (list 'library kernel-root)))))
                         (lambda (path child)
                           (let (existing (hash-get (reader-session-kernel-contexts session) path))
                             (or (not existing) (eq? existing child))))
                         (lambda (child input owner assets initialization-current!)
                           (unless (hash-key? (reader-session-kernel-inputs session) child)
                             (set! (reader-session-kernel-source-count session) (+ (reader-session-kernel-source-count session) 1))
                             (hash-put! (reader-session-kernel-contexts session) (.ref input 'path) child)
                             (hash-put! (reader-session-kernel-inputs session) child input)
                             (hash-put! (reader-session-kernel-owners session) child owner)
                             (hash-put! (reader-session-kernel-data session) child assets)
                             (hash-put! (reader-session-kernel-initializers session) child initialization-current!)
                             (reader-add-input-guard! session input)
                             ;; Initialization support remains live after the
                             ;; transfer. A successful handoff is not approval
                             ;; for a later source or receiver mutation.
                             (set! (reader-session-guards session)
                               (cons (make-source-preparation #f #f #f #f
                                       initialization-current! #f #f) (reader-session-guards session)))
                             (for-each (lambda (asset)
                                         (reader-add-input-guard! session asset)
                                         (record-input! asset)) assets))
                           (reader-enroll-candidate! session initialization-current!))
                         (lambda (child)
                           (and (captured-tool-context? (reader-session-compiler-contexts session) child)
                                (begin (tool-context child #f) #t)))))))
                (context
                 (or retained
                     (let (target (source-wrapper original-path owner-root))
                       (dynamic-wind
                        (lambda () (when shared? (set! kernel-depth (+ kernel-depth 1))))
                        (lambda ()
                          (when (current-module-source-observer)
                            ((current-module-source-observer)
                              (list 'compiler-source-import-start path) 1))
                          (let (context (module-source-measure-operation 'reader-role-import
                                           (lambda () (gerbil-import target reload?))))
                            (execution-progress! (list 'source-import path) 1)
                            (when (current-module-source-observer)
                              ((current-module-source-observer)
                                (list 'compiler-source-import-end path
                                      (expander-context-id context)) 1))
                            ;; A canonical Gerbil expander context must never acquire
                            ;; private-source registration. The closure cut
                            ;; relies on this identity invariant, not a name.
                            (when (captured-tool-context? (reader-session-compiler-contexts session) context)
                              (error "private source resolved to canonical compiler tool" path))
                            (hash-put! (reader-session-kernel-contexts session) path context)
                            (let (input (hash-get input-paths path))
                              (unless (and input (equal? (.ref input 'path) path))
                                (error "private source input identity changed" path))
                              ;; Reuse the existing per-publication index;
                              ;; do not read every unrelated input's slots
                              ;; into the runtime dependency frame.
                              (unless (hash-key? (reader-session-kernel-inputs session) context)
                                (set! (reader-session-kernel-source-count session) (+ (reader-session-kernel-source-count session) 1)))
                              (hash-put! (reader-session-kernel-inputs session) context input))
                            (when source-tree
                              (let (owner ((.ref source-tree 'locate-owner) path))
                                (hash-put! (reader-session-kernel-owners session) context
                                  (if owner (list (.ref owner 'identity) (.ref owner 'root))
                                    (and kernel-root (within? kernel-root path)
                                         (list 'library kernel-root))))))
                            context))
                        (lambda () (when shared? (set! kernel-depth (- kernel-depth 1)))))))))
           (call-with-module-source-read-cache
             (lambda ()
               (reader-for-each-kernel-context session context
                 (lambda (child)
                   (let (input (hash-get (reader-session-kernel-inputs session) child))
                     (when input
                       ;; A retained import must also be authorized by
                       ;; this publication's selected source tree. The
                       ;; input's byte check cannot detect disabled or
                       ;; unselected owners in that tree.
                       (when (and retained source-tree)
                         ((.ref source-tree 'locate-owner) (.ref input 'path)))
                       (record-input! input)
                       ;; A retained context is usable only after its
                       ;; ACTUAL transitive input support passes afresh.
                       ((.ref input 'admit-current))))))))
           context))
       (def (source-context original-path reload?)
         (let (path (path-normalize original-path))
           (cond
            ((equal? path interface-path)
             (error "publication bootstrap cannot import its own interface" interface-path))
            ((hash-get (reader-session-tool-paths session) path)
             => (lambda (context) (tool-context context reload?)))
            ((within? root path)
             (when (> kernel-depth 0) (error "shared source cannot depend on Module implementation" path))
             ;; A nested declared window/Interface may introduce another
             ;; owner inside this directory. Never bypass that boundary by
             ;; treating every descendant as this Module's private library.
             (let (owner (and source-tree ((.ref source-tree 'locate-owner) path)))
               (if (and owner (not (equal? (path-strip-trailing-directory-separator root)
                                          (path-strip-trailing-directory-separator (.ref owner 'root)))))
                 (shared-context original-path (.ref owner 'root) reload?)
                 (shared-context original-path root reload? #f))))
            ((and source-tree ((.ref source-tree 'locate-owner) path))
             => (lambda (owner) (shared-context original-path (.ref owner 'root) reload?)))
            ;; The directory source-tree above has already refused actual
            ;; unselected/disabled Interface owners. An ownerless library
            ;; may therefore use the SAME package-kernel route across window
            ;; prefixes too. Bare SourceRefs retain their original boundary.
            ((and kernel-root (within? kernel-root path)
                  (or source-tree (not tree) (not (within? tree path))))
             ;; The window admits Modules, not private ownership of these
             ;; ownerless libraries. Preserve their native public-name
             ;; binding, including the original compiler association bridge.
             (when (and source-tree ((.ref source-tree 'within-window?) path))
               (unless (reader-prepare-public-dependency session path)
                 (public-dependency-input path #f #t)
                 (error "public source identity changed" path)))
             (shared-context original-path kernel-root reload?))
            (else
             ;; Public dependencies may expand a relative source import
             ;; before an Gerbil expander context has been cached. Reuse the canonical
             ;; library only if its declared identity resolves to this exact
             ;; source; a namespace label or arbitrary external path is not
             ;; sufficient. Core sources still use the confined paths above.
             (let (input (reader-prepare-public-dependency session path))
               (unless input
                 (error "source import leaves its Module and package kernel"
                        path (list 'module-root root 'kernel-root kernel-root
                                   'module-tree tree)))
               (when reload? (error "public dependency reload requires a fresh environment"))
               (let* ((id (.ref input 'compiler-identity))
                      (known (hash-get (reader-session-tool-contexts session) id))
                      (known-path (and known (module-context-path known))))
                 ;; Gerbil catalog membership is an exact context + path
                 ;; capability, not a namespace spelling. Returning this
                 ;; already imported context cannot run a new initializer.
                 (if (and known (string? known-path)
                          (equal? path (path-normalize known-path)))
                   (begin
                     (call-with-module-source-read-cache
                       (lambda ()
                         (for-each-build-module known
                           (lambda (child)
                             (let ((file (module-context-path child))
                                   (identity (expander-context-id child)))
                               (cond
                                ((and (symbol? identity)
                                      (yuanxu-library-identity? identity))
                                 (tool-context child #f))
                                ((and (string? file) (string=? (path-extension file) ".ss"))
                                 (unless (reader-prepare-public-dependency session (path-normalize file))
                                   (error "Gerbil dependency source identity changed" file)))))))))
                     known)
                   (begin
                     ;; A new canonical public initializer is OPEN before
                     ;; runtime expansion, including its transitive macros.
                     (when ((reader-session-candidate session))
                       (reader-open-boundary! session (list 'public-source path id known-path)))
                     (parameterize ((current-expander-module-import gerbil-import))
                       (gerbil-import original-path #f))))))))))
       (def (resolve-build!)
         (parameterize ((current-module-source-phase 'build-role-before)) (reader-current! session))
         (let* ((path (.ref prepared 'build-source))
                (input (yuanxu-prepare-module-build-source path void))
                (related (map (lambda (file)
                                (yuanxu-prepare-module-build-source file void))
                              (.ref prepared 'role-sources))))
           (let (value (module-prepared-source-binding input 'Build related role-imports?: #t
             compiler-tools: (list (reader-session-tool-contexts session) (reader-session-tool-paths session) (reader-session-tool-dependencies session)
                                   (reader-session-tool-observations session) (reader-session-compiler-contexts session))
             shared-contexts: (reader-session-kernel-contexts session) shared-inputs: (reader-session-kernel-inputs session)
             source-inputs: (cut record-source-observations! (reader-session-tool-observations session) <>)
             private-sources: (filter (lambda (entry)
               (and (not (and (.slot? entry 'kind) (eq? (.ref entry 'kind) 'data)))
                    ;; Reuse the exact admitted publication closure, including
                    ;; its kernel dependencies. Restricting this to owner roles
                    ;; loses their transitive imports once interception remains
                    ;; active. Gerbil tools retain their canonical checked contexts.
                    (not (hash-key? (reader-session-tool-paths session) (path-normalize (.ref entry 'path))))
                    (not (member (path-normalize (.ref entry 'path))
                                 (map path-normalize (.ref prepared 'role-sources))))))
               input-values)))
             (parameterize ((current-module-source-phase 'build-role-after)) (reader-current! session)) value)))
       (def deferred-roles (.ref prepared 'deferred-roles))
       (def (publication-import path (reload? #f))
         (cond
          ((and (string? path) (hash-key? artifacts (path-normalize path)))
           (gerbil-import path reload?))
          ((and (string? path) (string=? (path-extension path) ".ss"))
           (source-context path reload?))
          (else
           ;; Compiled libraries must retain their canonical Gerbil
           ;; import closure. Redirect only the caller's source
           ;; binding, never imports inside a compiled library.
           (when ((reader-session-candidate session))
             (let* ((requested (syntax-e path))
                    (text (and (symbol? requested) (symbol->string requested)))
                    (id (and text (> (string-length text) 1)
                             (char=? (string-ref text 0) #\:)
                             (string->symbol (substring text 1 (string-length text))))))
               (unless (or (and id (hash-get (reader-session-tool-contexts session) id))
                           (and (string? requested)
                                (hash-get (reader-session-tool-paths session) (path-normalize requested))))
                 (reader-open-boundary! session (list 'uncatalogued-import path id)))))
           (let* ((context (module-source-measure-operation 'reader-native-import
                             (lambda () (parameterize ((current-expander-module-import gerbil-import))
                               (gerbil-import path reload?)))))
                  (identity (expander-context-id context))
                  (artifact-path (module-context-path context))
                  ;; Captured tools already carry their exact runtime
                  ;; identity. Do not parse their optional checkout merely
                  ;; to discover that the tool branch below needs no owner
                  ;; lookup. tool-context separately handles explicit build
                  ;; source demand and its fresh original input guards.
                  (owned-path
                    (and (not (hash-key? (reader-session-tool-contexts session) identity))
                         (if (and (string? artifact-path)
                                  (string=? (path-extension artifact-path) ".ss"))
                           artifact-path
                           (module-source-measure-operation 'reader-source-resolution
                             (lambda () (module-build-source-path context compiler-core-root))))))
                  (owner (and source-tree owned-path
                              ((.ref source-tree 'locate-owner) owned-path))))
             ;; Symbol and exact source-path imports share the same
             ;; observed compiler-context and currentness boundary.
             (cond
              ((hash-key? (reader-session-tool-contexts session) identity) (tool-context context reload?))
              (owner (source-context owned-path reload?))
              (else
               (let (source
                     (or (and package-root (module-build-source-path context package-root))
                         ;; A nested native package does not exhaust the
                         ;; source Context's already admitted kernel. This
                         ;; is declared authority, not an ancestor search or
                         ;; permission to rebuild installed prerequisites.
                         (and kernel-root (not (equal? kernel-root package-root))
                              (module-build-source-path context kernel-root))))
                 (if source (source-context source reload?) context))))))))
       (def (resolve-role role names)
         (reader-current! session 'role-entry)
         (def created? (not (file-exists? directory)))
         (dynamic-wind
           (lambda () (when created? (create-directory directory)))
           (lambda ()
             (parameterize ((current-expander-context (make-top-context))
                            (current-expander-compile compile)
                            (current-expander-eval evaluate)
                            (current-configuration-input-observer record-data!)
                            (current-expander-module-import publication-import))
               ;; Use the SAME confined context and source-input registry as
               ;; eager publication. Symbol imports must not create a second
               ;; public copy of an already admitted private role or kernel.
               (def path (path-expand (string-append (symbol->string role) ".ss") root))
               (def context (source-context path #f))
               ;; The runtime context owns its initializer promise. Reuse it
               ;; after wrapper cleanup without resolving a deleted file.
               (eval-module context)
               (hash-put! (reader-session-kernel-data session) context
                 (filter (lambda (input)
                           (and (.slot? input 'kind) (eq? (.ref input 'kind) 'data))) input-values))
               (def value
                 (parameterize ((current-expander-context context))
                   (module-role-values names)))
               (hash-put! (reader-session-dependencies session) interface-path (reverse input-values))
               (reader-current! session 'role-return)
               (release-reader-expansions! completed)
               value))
           (lambda () (when created? (remove-reader-tree directory)))))
       (dynamic-wind
        (lambda () (create-directory directory))
        (lambda ()
          (for-each
            (lambda (path)
              ;; The runtime import hook below already resolves a retained
              ;; role context and projects its CURRENT dependency registry.
              ;; Do not parse/write an unused wrapper for that same context.
              (unless (hash-key? (reader-session-kernel-contexts session) (path-normalize path))
                (source-wrapper (path-normalize path) root)))
            (if deferred-roles '() (.ref prepared 'role-sources)))
          (reader-enroll-candidate! session (.ref prepared 'admit-current))
          (parameterize ((current-module-source-phase 'declaration-inputs)) (reader-current! session))
          (let (wrapper (write-wrapper interface-path (reader-body (.ref prepared (if deferred-roles 'deferred-reader-forms 'reader-forms))) (.ref prepared 'compiler-identity)))
            (parameterize
                ((current-configuration-input-observer record-data!)
                 (current-expander-compile compile)
                 (current-expander-eval evaluate)
                 (current-expander-context (make-top-context))
                 (current-module-build-resolver resolve-build!)
                 (current-module-role-resolver resolve-role)
                 (current-expander-module-import
                  publication-import))
              ;; Native import expansion records the complete confined
              ;; private closure without evaluating its runtime role values.
              ;; Public-only delayed roles retain their existing cold path.
              (for-each (lambda (path) (source-context path #f))
                        (.ref prepared 'deferred-import-sources))
              (observe-reader-work 'reader-interface-start 'reader-interface-end
                (lambda () (eval-syntax `(import ,wrapper))))
              (let (value (eval-syntax (.ref prepared 'binding)))
                (parameterize ((current-module-source-phase 'declaration-after)) (reader-current! session))
                (def result (if consume (consume source-value value) value))
                ;; A deferred Build resolver shares this outer interpreter
                ;; frame. Do not retain the completed candidate's support
                ;; tables and producer continuation through that resolver.
                (set! consume #f)
                (set! (reader-session-evaluated-interface-bindings session)
                  (+ (reader-session-evaluated-interface-bindings session) (release-reader-expansions! completed)))
                (when (current-module-source-observer)
                  ;; Geometric, cache-free attribution of actual Gerbil roots.
                  ;; Inspect only existing tables/code pointers; do not walk
                  ;; binding values, force promises or clear compiler state.
                  (let (count (reader-session-publication-prepared-count session))
                    (when (and (> count 0) (= (bitwise-and count (- count 1)) 0))
                      (let ((bindings 0) (bodies 0))
                        (hash-for-each
                          (lambda (_path context)
                            (set! bindings (+ bindings (hash-length (expander-context-table context))))
                            (when (module-context-code context) (set! bodies (+ bodies 1))))
                          (reader-session-kernel-contexts session))
                        ((current-module-source-observer)
                          (list 'reader-binding-roots
                            (cons 'publications count)
                            (cons 'private-bindings bindings)
                            (cons 'evaluated-interface-bindings (reader-session-evaluated-interface-bindings session))
                            (cons 'private-code-bodies bodies)) 1))))
                  ;; Counts describe this reader's actual retention roots;
                  ;; observers never receive the context/syntax objects.
                  ((current-module-source-observer)
                    (list 'reader-retention
                      (cons 'tools (hash-length (reader-session-compiler-contexts session)))
                      (cons 'private-contexts (hash-length (reader-session-kernel-contexts session)))
                      ;; No per-root transitive topology copies are retained.
                      (cons 'dependency-closures 0)
                      (cons 'dependency-contexts 0)
                      (cons 'prepared-publications (reader-session-publication-prepared-count session))
                      (cons 'prepared-public-dependencies (reader-session-public-prepared-count session))
                      (cons 'source-objects (reader-session-kernel-source-count session))
                      (cons 'source-guards (length (reader-session-guards session)))) 1)
                  ((current-module-source-observer)
                    (list 'publication-end interface-path) 1))
                ;; Include the already prepared roles as well as private
                ;; dependencies. Build projection must not allocate a second
                ;; header/guard object for the very same observed source.
                (hash-put! (reader-session-dependencies session) interface-path (reverse input-values))
                result))))
        (lambda () (remove-reader-tree directory)))))))
