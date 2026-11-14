;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Filesystem source preparation. No eval, compiler, dynamic import or runtime Loader.
(import (runtime: :clan/poo/object)
        (only-in :gerbil/runtime/mop class-of)
        (only-in :gerbil/runtime/error Error::t)
        (only-in :gerbil/runtime/gambit current-readtable)
        (only-in :gerbil/runtime/syntax __*readtable*)
        (only-in :std/list/list delete-duplicates/hash any foldl length<=n?)
        (only-in :tao3k/yuanxu/module-system/source/preparation
                 module-source-package-prefix module-source-package-info)
        (only-in :tao3k/yuanxu/module-system/source/collection yuanxu-module-source-collection-optional-entrypoint)
        (only-in :tao3k/yuanxu/module-system/source/role-forms module-publication-role-imports)
        (only-in :clan/poo/prototype-map prototype-map prototype-map-ref prototype-map-put)
        (only-in :clan/poo/slot-observation slot-read-observers-compatible?)
        :tao3k/yuanxu/module-system/source/objects
        :tao3k/yuanxu/module-system/source/admission
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-object-policies
                 module-source-text-guard)
        :tao3k/yuanxu/module-system/source/init)
(export module-directory-context directory-candidate-guard? directory-candidate-guard-invoke)
(defstruct directory-source (value current?) final: #t)
(defstruct directory-decision (value current?) final: #t)
(defstruct directory-snapshot (children child-index interface?) final: #t)
(defstruct directory-candidate-guard (invoke) final: #t)
(def (directory-path-current source-current? checks)
  ;; Allocate outside locate-source's collecting frame: a retained SourceRef
  ;; must not retain that frame, its box or another located receiver.
  (lambda () (and (source-current?) (andmap (lambda (check) (check)) checks))))
(def (source-parts id)
  (let (parts (string-split (symbol->string id) #\/))
    (unless (and (pair? parts) (andmap module-source-name? parts))
      (error "invalid module directory identity" id))
    parts))
(def (module-directory-context path publication-reader
                              publication-prepares-source?: (publication-prepares-source? #f))
  (let ((observations '()) (directories (make-hash-table)) (sources (make-hash-table)))
    (def location-guards (make-parameter '()))
    (def (enroll-location! guard)
      (for-each (lambda (frame) (set-box! frame (cons guard (unbox frame))))
                (location-guards)))
    ;; Observations include negative lookups and immediate child names. They are
    ;; checked at the explicit publication boundary, not on every cached slot read.
    (def (observe! reader file (local? #t) (text? #f))
      (let (value (reader file))
        (def guard
          (if text?
            (let (check! (module-source-text-guard file value))
              (lambda () (module-source-measure-operation 'source-init-current check!)))
            (lambda () (equal? value (module-source-observe reader file)))))
        (set! observations (cons (cons local? guard) observations))
        (when local? (enroll-location! guard))
        value))
    (def (directory-names directory)
      (unless (eq? (module-source-type directory) 'directory) (error "module source is not a directory" directory))
      (list-sort string<? (directory-files directory)))
    (def (closed-directory-observation?)
      (and (not (current-module-source-observer))
           (slot-read-observers-compatible? '())
           (object-construction-current?)
           (not (module-source-window-preserved? void))))
    (def (snapshot directory)
      (if (hash-key? directories directory)
        (hash-ref directories directory)
         (let* ((reuse-kind? (closed-directory-observation?))
                (first-link #f)
                (unchecked '())
                (names (observe! directory-names directory #f))
                (children
                 (filter (lambda (name)
                           (if (module-source-name? name)
                             (let (kind (module-source-type (path-expand name directory)))
                               (when (and reuse-kind? (not first-link) (eq? kind 'symbolic-link))
                                 (set! first-link name))
                               (eq? kind 'directory))
                             (begin
                               (when (and reuse-kind? (not first-link))
                                 (set! unchecked (cons name unchecked)))
                               #f))) names)))
           (unless (= (length children)
                      (length (delete-duplicates/hash (map string-downcase children))))
             (error "case-colliding module directories" directory children))
           ;; Preserve collision priority. Check unobserved names in order up
           ;; to the first known symlink, including names excluded as modules.
           (for-each (lambda (name)
                       (when (eq? (module-source-type (path-expand name directory)) 'symbolic-link)
                         (error "symlink in module source tree" directory name)))
                     (if reuse-kind? (reverse unchecked) names))
           (when first-link
             (error "symlink in module source tree" directory first-link))
           ;; Whole listings establish global namespace/collision policy, not
           ;; each private candidate's path support. locate-source* enrolls
           ;; actual path kinds even when this snapshot is already present.
           ;; Keep enumeration order while indexing wide membership queries.
           ;; Use the same small-branch cutoff as POO's compact prototype map.
           (let* ((child-index (and (not (length<=n? children 8))
                                    (list->hash-table (map (cut cons <> #t) children))))
                  (value (make-directory-snapshot children child-index
                                                  (and (member "interface.ss" names) #t))))
             (hash-put! directories directory value)
             value))))
    (def (intent-root intent file)
        (let (configured (.ref intent 'root))
          (if (and (not (.ref intent 'root-explicit?)) (string=? configured "modules")
                   (string=? (path-strip-directory
                               (path-strip-trailing-directory-separator (path-directory file))) "modules"))
            (path-directory file)
            (module-init-source-root intent file))))
    (let* ((input (path-expand path))
           (init-path
            (if (eq? (module-source-type input) 'regular)
              input
              (let* ((inside (path-expand "init.ss" input))
                     (beside (path-expand "../init.ss" input))
                     (inside-type (observe! module-source-type inside))
                     (beside-type
                      (and (string=? (path-strip-directory
                                      (path-strip-trailing-directory-separator input)) "modules")
                           (observe! module-source-type beside))))
                (cond
                 ((and inside-type beside-type)
                  (error "ambiguous init.ss authority; pass the exact init path" inside beside))
                 (inside-type inside)
                 (beside-type beside)
                 (else #f)))))
           (_declared (unless init-path (error "module window requires a yuanxu! declaration" input)))
           (intent-value
             (module-init-intent
               (call-with-input-string (observe! module-source-read init-path #t #t) read-all) init-path))
           (root-path (intent-root
                        (if (.slot? intent-value 'windows)
                          (car (.ref intent-value 'windows)) intent-value) init-path))
           (decisions (.ref intent-value 'decisions))
           (selected-values (map (lambda (row) (.ref row 'identity))
                                 (filter (lambda (row) (not (.ref row 'disabled?))) decisions)))
           (denied-values (map (lambda (row) (.ref row 'identity))
                               (filter (lambda (row) (.ref row 'disabled?)) decisions)))
           (generation-value (symbol->string (gensym 'module-directory-))))
      (def windows (and (.slot? intent-value 'windows) (.ref intent-value 'windows)))
      ;; Literal tag/directory inspection has no publication reader and grants
      ;; no runtime authority. Native owner admission is demanded by a reader.
      (def qualified-owners? (and windows publication-reader))
      ;; These are the parser's own inert objects, not evaluated user objects.
      ;; Full currentness and per-candidate location share revision records
      ;; for the same parser-owned objects, including nested decision flags.
      ;; An open observer can change the objects between the original reads.
      (defvalues (intent-current? policies)
        (if (and (object-construction-current?)
                 (not (current-module-source-observer))
                 (slot-read-observers-compatible? '()))
          (module-source-object-policies
            (cons (cons intent-value (or windows '()))
                  (map (lambda (row) (list row (.ref row 'selection))) decisions)))
          (values
            (module-source-object-policy
              (append (list intent-value) decisions (or windows '())
                      (map (lambda (row) (.ref row 'selection)) decisions)))
            #f)))
      (def (window-root window)
        (module-init-source-root window init-path))
      (def (row-window row)
        (and windows row
             (find (lambda (window) (eq? (.ref window 'mount) (.ref row 'window))) windows)))
      (def (row-root row)
        (let (window (row-window row)) (if window (window-root window) root-path)))
      ;; The existing indexes carry full native owner keys across mounted
      ;; roots. A single-root Context already supplies its implicit root.
      (def native-prefixes (make-hash-table-eq))
      (when qualified-owners?
        (for-each (lambda (window)
                    (hash-put! native-prefixes window
                      (observe! module-source-package-prefix (window-root window)))) windows))
      (when qualified-owners?
        (let (owners (make-hash-table))
          (for-each (lambda (window)
                      (def prefix (hash-ref native-prefixes window))
                      (when (hash-get owners prefix)
                        (error "native root identity has multiple source owners" prefix))
                      (hash-put! owners prefix (window-root window))) windows)))
      (def (row-name row)
        (if (.slot? row 'declaration-id) (.ref row 'declaration-id) (.ref row 'identity)))
      (def (owner-key window name (row #f))
        (if (not qualified-owners?) name
          (let ((declared (and row (.ref row 'source-root)))
                (prefix (hash-ref native-prefixes window)))
            (if declared
              (string->symbol
                (string-append
                  (observe! module-source-package-prefix (path-expand declared (path-directory init-path)))
                  "interface"))
              (string->symbol (string-append prefix (symbol->string name) "/interface"))))))
      ;; Preserve the original parser-owned rows and their read policies. These
      ;; inert projections change index keys, never the authored declaration.
      (when qualified-owners?
        (set! decisions
          (map (lambda (row)
                 (def name (.ref row 'identity))
                 (def window (row-window row))
                 (def owner (owner-key window name row))
                 (.cc row 'declaration-id name 'identity owner)) decisions))
        (set! selected-values (map (cut .ref <> 'identity)
                                  (filter (lambda (row) (not (.ref row 'disabled?))) decisions)))
        (set! denied-values (map (cut .ref <> 'identity)
                                (filter (cut .ref <> 'disabled?) decisions))))
      (def scoped-intent (if qualified-owners? (.cc intent-value 'decisions decisions) intent-value))
      ;; Keep every signed decision in the scope-demand graph, including
      ;; withdrawals. Unrelated Core-only roots stay lazy until demanded.
      (def feature-roots
        (filter-map
          (lambda (row)
            (and (not (.ref row 'disabled?))
                 (pair? (.ref (.ref row 'selection) 'selection-flags))
                 (.ref row 'identity)))
          decisions))
      (defvalues (key-intact? key-policies)
        (if qualified-owners?
          (module-source-object-policies
            (cons (cons scoped-intent windows)
                  (map (lambda (row) (list row (.ref row 'selection))) decisions)))
          (values #f #f)))
      (def source-owners (make-hash-table))
      (def decision-index (list->hash-table
                             (map (lambda (row current?)
                                    (cons (.ref row 'identity)
                                      (make-directory-decision row
                                        (or current? (module-source-object-policy
                                                       (list row (.ref row 'selection)))))))
                                  decisions (cond (key-policies (cdr key-policies))
                                                  (policies (cdr policies))
                                                  (else (map (lambda (_) #f) decisions))))))
      (def (decision-row id)
        (let (entry (hash-get decision-index id))
          (and entry (directory-decision-value entry))))
      (def (window-key window name)
        (let (bound (and qualified-owners?
                          (decision-row (cons (.ref window 'mount) name))))
          (if bound (.ref bound 'identity) (owner-key window name))))
      (when windows
        (let (seen (make-hash-table-eq))
          (for-each (lambda (row)
                      (def key (.ref row 'identity))
                      (when (hash-get seen key)
                        (error (if qualified-owners?
                                 "native module identity has multiple source owners"
                                 "repeated metadata names require a root-qualified reader") key))
                      (hash-put! seen key #t)
                      (when (and qualified-owners? (.ref row 'source-root))
                        ;; An explicit @ location changes the compiler identity.
                        ;; Its local name still routes to the same guarded row.
                        (hash-put! decision-index (cons (.ref row 'window) (row-name row))
                          (hash-ref decision-index key)))) decisions)))
      (def (key-window key)
        (and windows
          (let ((row (decision-row key)) (text (symbol->string key)))
            (if row (row-window row)
              (if (not qualified-owners?)
                (let (matches
                      (filter (lambda (window)
                                (eq? (observe! module-source-type
                                       (path-expand text (window-root window))) 'directory)) windows))
                  (when (and (pair? matches) (pair? (cdr matches)))
                    (error "metadata reference requires a root-qualified reader" key))
                  (and (pair? matches) (car matches)))
              (let ((matches (filter (lambda (window)
                                       (and (string-prefix? (hash-ref native-prefixes window) text)
                                            (string-suffix? "/interface" text))) windows)))
                (and (pair? matches)
                     (car (list-sort (lambda (left right)
                                       (> (string-length (hash-ref native-prefixes left))
                                          (string-length (hash-ref native-prefixes right)))) matches)))))))))
      (def (key-name key)
        (if (not qualified-owners?) key
          (let ((row (decision-row key)) (window (key-window key)))
            (if row (row-name row)
              (if window
                (let ((text (symbol->string key)) (prefix (hash-ref native-prefixes window)))
                  (string->symbol (substring text (string-length prefix) (- (string-length text) 10))))
                (error "module identity is outside declared native roots" key))))))
      (def (resolve-request-root key)
        (if (or (not qualified-owners?) (key-window key)) key
          (let ((matches
                 (filter-map
                   (lambda (window)
                     (def candidate (window-key window key))
                     (and (or (decision-row candidate)
                              (and (eq? (.ref window 'mode) 'auto)
                                   (eq? (observe! module-source-type
                                           (path-expand (symbol->string key) (window-root window))) 'directory)))
                          candidate)) windows)))
            (unless (= (length matches) 1)
              (error "unqualified module root requires one native owner" key matches))
            (car matches))))
      (def (resolve-reference owner required)
        (if (or (not qualified-owners?) (key-window required)) required
          (let (window (key-window owner))
            (unless window (error "dependency owner has no native root" owner))
            (window-key window required))))
      ;; A Profile is an opt-in discovery pass within its source window.
      ;; Keep the resulting roots in the existing namespace projection.
      (def profile-roots (make-hash-table-eq))
      (def (profile-tag window)
        (and (.slot? window 'profile) (.ref window 'profile)))
      (def (interface-tags file)
        (module-interface-tags file (module-source-read file)))
      (def (observe-profile-tags! file)
        (if (or (current-module-source-observer) (not (eq? (current-readtable) __*readtable*)))
          (observe! interface-tags file #f)
          (let* ((text (string-copy (module-source-read file)))
                 (tags (module-interface-tags file text)))
            ;; Keep the original evidence immutable. Every independent
            ;; window reads fresh bytes. Changed bytes still take the literal
            ;; decoder path, even for an owner outside the selected closure.
            (set! observations
              (cons (cons #f
                      (lambda ()
                        (if (or (current-module-source-observer)
                                (not (eq? (current-readtable) __*readtable*)))
                          (equal? tags (module-source-observe interface-tags file))
                          ;; The reader already owns the physical path entry
                          ;; in this window. Compare this guard's own tag evidence.
                          (let (observed (module-source-read file))
                            (or (string=? text observed)
                                (equal? tags (module-interface-tags file observed)))))))
                observations))
            tags)))
      (def (select-profile window directory)
        (def tag (profile-tag window))
        (when tag
          (let ((selected '()))
            (let walk ((parent directory) (prefix ""))
              (for-each
                (lambda (name)
                  (let* ((child (path-expand name parent))
                         (id (string->symbol (string-append prefix name)))
                         (node (snapshot child))
                         (file (path-expand "interface.ss" child))
                         (classified (and (directory-snapshot-interface? node)
                                          (observe-profile-tags! file))))
                    (if classified
                      (when (and (not (decision-row (window-key window id)))
                                 (memq tag classified))
                        (set! selected (cons id selected)))
                      (walk child (string-append prefix name "/")))))
                (directory-snapshot-children (snapshot parent))))
            (hash-put! profile-roots window (reverse selected)))))
      (when (any profile-tag (or windows (list intent-value)))
        (module-source-measure-operation 'profile-interface-scan
          (lambda ()
            (for-each (lambda (window)
                        (select-profile window (if windows (window-root window) root-path)))
                      (or windows (list intent-value))))))
      (def (roots-for window)
        (or (hash-get profile-roots window) '()))
      (def (module-directory? directory node)
        (and node (directory-snapshot-interface? node)
             (observe! (lambda (source)
                         (module-interface-declaration? source (module-source-read source)))
                       (path-expand "interface.ss" directory))))
      (def (auto-owners window)
        (def intent (or window intent-value))
        (if (or (not (eq? (.ref intent 'mode) 'auto)) (profile-tag intent)) '()
          (let walk ((directory (if window (window-root window) root-path)) (prefix ""))
            (foldr append '()
              (map (lambda (name)
                     (def child (path-expand name directory))
                     (def path (string-append prefix name))
                     (def owner (window-key window (string->symbol path)))
                     (if (module-directory? child (snapshot child))
                       (if (decision-row owner) '() (list owner))
                       (walk child (string-append path "/"))))
                   (directory-snapshot-children (snapshot directory)))))))
      (let ((profile-selected
               (foldr append '()
                 (map (lambda (window) (map (cut window-key window <>) (roots-for window)))
                      (or windows (list intent-value))))))
        ;; A category is selected across its declared windows. A dependency
        ;; window may have no matching roots; its differently tagged owners
        ;; remain eligible through Gerbil imports. Reject a miss only
        ;; when that category has no roots in ANY participating window.
        (for-each
          (lambda (window)
            (let (tag (profile-tag window))
              (when (and tag
                         (not (any (lambda (candidate)
                                     (and (eq? (profile-tag candidate) tag)
                                          (pair? (roots-for candidate))))
                                   (or windows (list intent-value)))))
                (error "Profile has no matching Module Interface" tag init-path))))
          (or windows (list intent-value)))
        (unless (= (length profile-selected) (length (delete-duplicates/hash profile-selected)))
          (error "profile owner occurs in multiple windows" init-path))
        (set! selected-values (append selected-values profile-selected)))
      ;; Index declared ownership once. Locating an imported private owner walks
      ;; path ancestors, not the module list or another filesystem search tree.
      (def direct-owner-root
        (and (pair? decisions) (not windows)
             (eq? (.ref intent-value 'mode) 'explicit)
             (closed-directory-observation?)
             (let (before observations)
               (with-catch
                 (lambda (cause)
                   ;; Leave the owner pass ahead of the original root refusal.
                   (if (or (eq? (class-of cause) Error::t) (os-exception? cause))
                     (begin (set! observations before) #f)
                     (raise cause)))
                 (lambda ()
                   (let (root (observe! path-normalize root-path))
                     (and (string-suffix? "/" root)
                          (let* ((children (.ref (snapshot root-path) 'child-names))
                                 (index (make-hash-table size: (length children))))
                            (for-each (lambda (name) (hash-put! index name #t)) children)
                            (cons root index)))))))))
      (def (direct-owner-key name)
        (and direct-owner-root (hash-key? (cdr direct-owner-root) name)
             (not (char=? (string-ref name 0) #\~))
             (string-append (car direct-owner-root) name)))
      (for-each
       (lambda (row)
         (let* ((id (.ref row 'identity))
                (declared (.ref row 'source-root))
                (name (and (not declared) (symbol->string (row-name row))))
                (direct (and name (direct-owner-key name)))
                (directory (and (not direct)
                                (if declared (path-expand declared (path-directory init-path))
                                  (path-expand name (row-root row)))))
                (key (or direct (path-strip-trailing-directory-separator (path-normalize directory)))))
           (when (hash-key? source-owners key)
             (error "duplicate declared module source owner" id
                    (or directory (path-expand name (row-root row))) init-path))
           ;; Keep denied declarations in this SAME index. Their directory must
           ;; never become an ownerless library merely because Interface is absent.
           (hash-put! source-owners key
             (.o identity: id root: key disabled?: (.ref row 'disabled?))))) decisions)
      ;; An auto-window owner may be referenced by types before its publication
      ;; is demanded. Invert only the requested path; do not enumerate modules.
      (def auto-owner-roots
        (map (lambda (directory)
               (path-strip-trailing-directory-separator (path-normalize directory)))
             (if windows
               (map window-root (filter (lambda (window) (eq? (.ref window 'mode) 'auto)) windows))
               (if (eq? (.ref intent-value 'mode) 'auto) (list root-path) '()))))
      (def (auto-source-owner directory)
        (def identities
          (delete-duplicates/hash
            (filter-map
              (lambda (root)
                (def prefix (string-append root "/"))
                (and (string-prefix? prefix directory)
                     (let (id (string->symbol
                                (substring directory (string-length prefix) (string-length directory))))
                       ;; Explicit declarations (including disable) own identity;
                       ;; an auto directory must never shadow their source.
                       (let* ((window (and windows (find (lambda (window) (string=? root
                                                    (path-strip-trailing-directory-separator
                                                      (path-normalize (window-root window))))) windows)))
                              (key (window-key window id)))
                         (and (not (decision-row key)) key))))) auto-owner-roots)))
        (and (pair? identities)
             (begin
               (when (pair? (cdr identities))
                 (error "ambiguous imported module owner" directory identities))
               ;; Reuse the normal locator and its policy/currentness carrier.
               ;; It registers ownership only after path/style admission.
               (locate-source (car identities))
               (hash-get source-owners directory))))
      (def declared-window-roots
        (if windows (map window-root windows) (list root-path)))
      (def (source-owner path)
        (let loop ((directory (path-strip-trailing-directory-separator
                               (path-directory (path-normalize path)))))
          (let (owner (hash-get source-owners directory))
            (cond
             (owner
              (when (.ref owner 'disabled?)
                (error "source import belongs to a disabled Module" path (.ref owner 'identity)))
              owner)
             (else
              ;; One kind observation supplies BOTH auto eligibility and the
              ;; explicit-window refusal. No second probe or boundary registry.
              (let (kind (and (any (lambda (root) (inside? directory root)) declared-window-roots)
                              (observe! module-source-type (path-expand "interface.ss" directory))))
                (if (and kind
                         (begin
                           (unless (eq? kind 'regular)
                             (error "Module interface is not a regular file" directory))
                           (observe! (lambda (file)
                                       (module-interface-declaration? file (module-source-read file)))
                                     (path-expand "interface.ss" directory))))
                  (begin
                    (unless (eq? kind 'regular)
                      (error "Module interface is not a regular file" directory))
                    (or (and (pair? auto-owner-roots) (auto-source-owner directory))
                        (error "source import belongs to an unselected Module" path directory)))
                  ;; Absence is observed too: creating Interface later makes
                  ;; this ownerless classification stale. Never fall through
                  ;; an actual closed boundary to a selected ancestor.
                  (let (parent (path-strip-trailing-directory-separator (path-directory directory)))
                    (and (not (equal? parent directory)) (loop parent))))))))))
      ;; One immutable projection per declared window, not an admission cache.
      ;; Currentness observes the yuanxu! declaration bytes.
      (def (canonical path)
        (path-strip-trailing-directory-separator (path-normalize path)))
      (def (inside? path root)
        (let ((path (canonical path)) (root (canonical root)))
          (or (string=? path root)
              (string-prefix? (string-append root "/") path))))
      (def (declared-kernel root)
        (def own (path-directory init-path))
        (if (inside? root own) (path-normalize own)
          (let* ((package (observe! module-source-package-info root))
                 (candidates (delete-duplicates/hash
                               (append (list (path-expand "init.ss" root) (path-expand "../init.ss" root))
                                       (if package (list (path-expand "init.ss" (car package))) '()))))
                 (origins
                  (filter-map
                    (lambda (file)
                      (and (eq? (observe! module-source-type file) 'regular)
                        (let* ((text (observe! module-source-read file))
                               (intent (with-catch (lambda (_) #f)
                                         (lambda () (module-init-intent
                                                      (call-with-input-string text read-all) file)))))
                          (and intent
                            (let (roots
                                   (if (.slot? intent 'windows)
                                     (map (lambda (window) (module-init-source-root window file))
                                          (.ref intent 'windows))
                                     (list (intent-root intent file))))
                              (and (any (lambda (path) (inside? root path)) roots)
                                   (path-normalize (path-directory file)))))))) candidates)))
            (when (and (pair? origins) (pair? (cdr origins)))
              (error "ambiguous declared source window origin" root origins))
            (if (pair? origins) (car origins) (path-normalize root)))))
      (def kernel-roots
        (list->hash-table
          (map (lambda (root) (cons (canonical root) (declared-kernel root)))
               (if windows (map window-root windows) (list root-path)))))
      ;; A foreign kernel is admitted by the init that owns the declared
      ;; directory. A bare external directory grants only its own source tree.
      (def package-kernels
        (filter-map (lambda (root)
                      (let (kernel (hash-ref kernel-roots (canonical root)))
                        (and (not (inside? root (path-directory init-path)))
                             (not (equal? (canonical root) (canonical kernel)))
                             kernel)))
                    declared-window-roots))
      ;; A window prefix is not Module ownership. The indexed ancestor walk
      ;; above refuses actual closed boundaries; #f denotes an ordinary library.
      (def source-tree
        (.o locate-owner: source-owner package-roots: (delete-duplicates/hash (map cdr (hash->list kernel-roots)))
            package-kernel: (lambda (file) (find (lambda (root) (inside? file root)) package-kernels))
            within-window?:
            (lambda (file) (any (lambda (root) (inside? file root)) declared-window-roots))))
      (def (locate-source* id)
        (source-parts id)
        (if (hash-key? sources id)
          (let (entry (hash-ref sources id))
            (unless ((directory-source-current? entry))
              (error "stale directory SourceRef" id))
            (directory-source-value entry))
         (let ()
           (let* ((row (decision-row id))
                  (window (key-window id))
                  (local-id (key-name id))
                  (_eligible
                   (when (and windows (not row)
                              (not (and window (eq? (.ref window 'mode) 'auto))))
                     (error "module is outside explicit directory windows" id)))
                  (owner-root (if row (row-root row)
                                  (if window (window-root window) root-path)))
                  (declared (and row (.ref row 'source-root)))
                  (origin (and declared (path-expand declared (path-directory init-path)))))
             (def (publish raw-child raw-collection-root (checked-kind? #f))
               (unless (or checked-kind? (eq? (observe! module-source-type raw-child) 'directory))
                 (error "module source is not a directory" raw-child))
               (let* ((child (observe! path-normalize raw-child))
                      (collection-root (path-normalize raw-collection-root))
                      (leaf (snapshot child)))
                 (unless (directory-snapshot-interface? leaf) (error "module has no interface.ss" id child))
                 (unless (eq? (observe! module-source-type (path-expand "interface.ss" child)) 'regular)
                   (error "module interface is not a regular file" id child))
                 ;; The runtime publication preparer owns role/authoring
                 ;; admission before expansion. In that paired path locating
                 ;; an owner is only inert directory/init interpretation.
                 ;; Custom readers retain the original source admission here.
                 (unless publication-prepares-source?
                   ((.ref yuanxu-default-module-style-policy 'validate)
                    yuanxu-default-module-style-policy local-id child
                    (lambda (file) (observe! module-source-read file))))
                 (hash-put! source-owners (path-strip-trailing-directory-separator child)
                            (.o identity: id root: child disabled?: #f))
                 (let (value (make-yuanxu-module-source-ref
                              'local (path-expand "interface.ss" child)
                              (append (if qualified-owners? (list (cons 'declaration-id local-id)) '())
                              (list (cons 'module-id id) (cons 'module-root child)
                                    (cons 'collection-root collection-root)
                                    (cons 'kernel-root (hash-ref kernel-roots (canonical owner-root)))
                                    ;; Mount is organization, never publication identity.
                                    (cons 'namespace-mount
                                      (if window (.ref window 'mount)
                                        (string->symbol
                                          (path-strip-directory
                                            (path-strip-trailing-directory-separator owner-root)))))
                                    (cons 'test-dir (.ref (or window intent-value) 'test-dir))
                                    (cons 'source-binding (if origin 'explicit 'directory))
                                    (cons 'source-tree source-tree)
                                    (cons 'init-source init-path) (cons 'generation generation-value)))))
                   ;; Replace the existing source-index payload with its owned
                   ;; identity support; do not build another source tree/cache.
                   (hash-put! sources id
                     (make-directory-source value
                       (module-source-object-policy (list value) reject-protocols?: #f)))
                   value)))
             ;; An explicit binding is authoritative. Never probe a local or Gerbil
             ;; fallback when it is absent, disabled, stale or malformed.
             (if origin
               (publish origin (path-directory (path-strip-trailing-directory-separator origin)))
               (let walk ((directory owner-root) (parts (source-parts local-id)))
                 (let* ((node (snapshot directory))
                        (index (directory-snapshot-child-index node)))
                   (unless (if index (hash-key? index (car parts))
                             (member (car parts) (directory-snapshot-children node)))
                     (error "module directory not found" id directory))
                   (let ((child (path-expand (car parts) directory))
                         (closed? (and (null? (cdr parts)) (closed-directory-observation?))))
                     (unless (eq? (observe! module-source-type child) 'directory)
                       (error "module path is not a directory" id child))
                     (if (pair? (cdr parts)) (walk child (cdr parts))
                       ;; The terminal kind was just observed and enrolled in
                       ;; the same location frame. Keep both checks on open paths.
                       (publish child owner-root (and closed? (closed-directory-observation?))))))))))))
      (def (locate-source id)
        (if (hash-key? sources id) (locate-source* id)
          (let* ((frame (box '()))
                 (value (parameterize ((location-guards (cons frame (location-guards))))
                          (locate-source* id)))
                 (entry (hash-ref sources id))
                 (source-current? (directory-source-current? entry))
                 (checks (unbox frame)))
            ;; Retain actual positive AND negative path demands in the existing
            ;; SourceRef carrier. No successful currentness result is retained.
            (set! (directory-source-current? entry)
              (directory-path-current source-current? checks))
            value)))
      (def (current-sources?)
        (def valid? #t)
        (hash-for-each
          (lambda (_id entry)
            (when valid? (set! valid? ((directory-source-current? entry))))) sources)
        valid?)
      (def (current-source? requested-generation)
        (with-catch (lambda (_exception) #f)
                    (lambda () (and (string=? requested-generation generation-value)
                                    (intent-current?)
                                    (or (not key-intact?) (key-intact?))
                                    (current-sources?)
                                    (module-source-measure-operation 'directory-current-observations
                                      (lambda ()
                                        (andmap (lambda (entry) ((cdr entry))) observations)))))))
      (def (tree resolve directory prefix (window #f) (branch-paths #f))
        (let* ((node (and (eq? (observe! module-source-type directory) 'directory) (snapshot directory)))
               ;; One immutable namespace generation, not another graph/cache.
               ;; Split declarations once at the mount; children retain only
               ;; their own suffixes rather than rescanning every selected id.
               (paths (or branch-paths
                          (map source-parts
                            (if window
                              (append
                                (map row-name
                                  (filter (lambda (row)
                                            (and (not (.ref row 'disabled?))
                                                 (eq? (.ref row 'window) (.ref window 'mount)))) decisions))
                                (roots-for window))
                              selected-values))))
               (declared (filter-map (lambda (path) (and (pair? path) (car path))) paths))
               (groups (foldl
                         (lambda (path index)
                           (if (null? path) index
                             (let (key (string->symbol (car path)))
                               (prototype-map-put index key
                                 (cons (cdr path) (prototype-map-ref index key '()))))))
                         (prototype-map '()) paths))
               (names (delete-duplicates/hash
                        (append (if (and node (not (profile-tag (or window intent-value)))
                                         (or (not window) (eq? (.ref window 'mode) 'auto)))
                                  (directory-snapshot-children node) '()) declared))))
          ;; Actual inspected declaration rows; diagnostic observers are optional.
          ;; No timer heartbeat, business resolution or persistent verdict.
          (when (current-module-source-observer)
            ((current-module-source-observer) 'namespace-declaration-rows (length paths)))
          (object<-fun
           (lambda (key)
             (let* ((text (symbol->string key)) (child (path-expand text directory))
                    (id (string->symbol (string-append prefix text)))
                    (owner (window-key window id))
                    (row (decision-row owner))
                    (children (reverse (prototype-map-ref groups key '()))))
               (when (and (member '() children) (pair? (cdr children)))
                 (error "module namespace has a leaf/branch collision" id))
               (when (and window row (not (eq? (.ref row 'window) (.ref window 'mount))))
                 (error "publication belongs to a different directory window"
                        id (.ref window 'mount) (.ref row 'window)))
               (if (and row (.ref row 'source-root)) (resolve owner)
                 (let (child-node (and (eq? (observe! module-source-type child) 'directory) (snapshot child)))
                   (if (and child-node (directory-snapshot-interface? child-node)
                            (or row (not publication-prepares-source?)
                                (module-directory? child child-node)))
                     (resolve owner)
                     (tree resolve child (string-append (symbol->string id) "/") window children))))))
           keys: (map string->symbol names))))
      ;; Capture the root metadata now, never recursively enumerate every module.
      (snapshot root-path)
      (when windows
        (for-each (lambda (window) (snapshot (window-root window))) windows))
      ;; Candidate location does not depend on every earlier located Module.
      ;; Root/init/window observations are fixed here; a requested decision and
      ;; its actual path support are checked separately. Full current-source?
      ;; remains mandatory before Graph visibility and around open callbacks.
      (def location-inputs
        (filter-map (lambda (entry) (and (car entry) (cdr entry))) observations))
      (def location-policy?
        (if policies (car policies)
          (module-source-object-policy (cons intent-value (or windows '())))))
      (def (candidate-location-current? requested-generation id)
        (with-catch (lambda (_exception) #f)
          (lambda ()
            (let ((decision (hash-get decision-index id)) (entry (hash-get sources id)))
              (when (current-module-source-observer)
                ((current-module-source-observer) 'candidate-location-checks 1))
              (and (string=? requested-generation generation-value)
                   (location-policy?)
                   (or (not key-policies) ((car key-policies)))
                   (or (not decision) ((directory-decision-current? decision)))
                   (andmap (lambda (check) (check)) location-inputs)
                   (or (not entry) ((directory-source-current? entry))))))))
      (.o generation: generation-value module-ids: selected-values selected: selected-values
          loader-roots: (append selected-values
                          (foldr append '() (map auto-owners (or windows '(#f)))))
          (feature-roots)
          denied-modules: denied-values intent: scoped-intent init-source: init-path source-root: root-path
          locate: (lambda (id) (locate-source (resolve-request-root id)))
          collect-entrypoint:
          (lambda (owner contributor parts)
            (def root (path-directory (yuanxu-module-source-ref-value (locate-source owner))))
            (def entry
              (yuanxu-module-source-collection-optional-entrypoint root owner contributor parts
                (lambda (path) (observe! module-source-type path))))
            (when entry
              ;; Expansion discovers these roles by convention. Include even
              ;; absent roles in the selected source epoch.
              (module-publication-role-imports (path-directory entry)
                (lambda (path) (observe! module-source-type path))))
            entry)
          resolve-module-id: resolve-reference resolve-root: resolve-request-root current?: current-source? candidate-current?: candidate-location-current?
          %candidate-guard:
          (lambda (generation id stale!)
            ;; Issued here over the actual directory check, never over a
            ;; caller's success callback. The linker owns refusal handling.
            (make-directory-candidate-guard
              (lambda ()
                (call-with-module-source-read-cache
                  (lambda ()
                    (unless (candidate-location-current? generation id)
                      (stale!)
                      (error "stale module location generation" generation)))))))
          eligible?: (lambda (id)
                       (let (row (decision-row id))
                         (and (not (and row (.ref row 'disabled?)))
                              (or row
                                  (if windows
                                    (let (window (key-window id)) (and window (eq? (.ref window 'mode) 'auto)))
                                    (eq? (.ref intent-value 'mode) 'auto)))
                              (begin (locate-source id) #t))))
          namespace:
          (lambda (resolve)
            (if windows
              (object<-fun
                (lambda (name)
                  (let (window (find (lambda (window) (eq? name (.ref window 'mount))) windows))
                    (unless window (error "unknown directory mount" name))
                    (tree resolve (window-root window) "" window)))
                keys: (map (cut .ref <> 'mount) windows))
              (if (eq? (.ref intent-value 'mode) 'auto) (tree resolve root-path "") #f)))
          read-publication:
          (or publication-reader
              (lambda (source) (error "no source publication reader supplied; runtime Loader is not connected" source)))))))
