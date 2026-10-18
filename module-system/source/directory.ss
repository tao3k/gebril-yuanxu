;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Filesystem source preparation. No eval, compiler, dynamic import or runtime Loader.
(import (only-in :clan/poo/object .o .ref .slot? object<-fun)
        (only-in :std/list/list delete-duplicates/hash any)
        :core/module-system/source/objects
        :core/module-system/source/admission
        :core/module-system/source/init)
(export module-directory-context)
(def (source-cache-ref cache key compute)
  (if (hash-key? cache key) (hash-ref cache key) (compute)))
(def (source-parts id)
  (let (parts (string-split (symbol->string id) #\/))
    (unless (and (pair? parts) (andmap module-source-name? parts))
      (error "invalid module directory identity" id))
    parts))
(def (module-directory-context path publication-reader)
  (let ((observations '()) (directories (make-hash-table)) (sources (make-hash-table)))
    ;; Observations include negative lookups and immediate child names. They are
    ;; checked at the explicit publication boundary, not on every cached slot read.
    (def (observe! reader file)
      (let (value (reader file))
        (set! observations (cons (lambda () (equal? value (reader file))) observations))
        value))
    (def (directory-names directory)
      (unless (eq? (module-source-type directory) 'directory) (error "module source is not a directory" directory))
      (list-sort string<? (directory-files directory)))
    (def (snapshot directory)
      (source-cache-ref directories directory
       (lambda ()
         (let* ((names (observe! directory-names directory))
                (children
                 (filter (lambda (name)
                           (and (module-source-name? name)
                                (eq? (module-source-type (path-expand name directory)) 'directory))) names))
                (value (.o path: directory child-names: children
                           interface?: (and (member "interface.ss" names) #t))))
           (unless (= (length children)
                      (length (delete-duplicates/hash (map string-downcase children))))
             (error "case-colliding module directories" directory children))
           ;; Refuse symlinks rather than accidentally traverse an escaping tree.
           (for-each (lambda (name)
                       (when (eq? (module-source-type (path-expand name directory)) 'symbolic-link)
                         (error "symlink in module source tree" directory name))) names)
           (hash-put! directories directory value)
           value))))
    (let* ((input (path-expand path))
           (init-path
            (if (eq? (module-source-type input) 'regular)
              (begin (unless (string=? (path-strip-directory input) "init.ss")
                       (error "expected init.ss or a module directory" input)) input)
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
           (intent-value (if init-path
                     (module-init-intent
                      (call-with-input-string (observe! module-source-read init-path) read-all) init-path)
                     (.o mode: 'auto root: "." init-source: #f decisions: '())))
           (root-path
            (if init-path
              ;; modules/init.ss defaults to itself; a root init.ss defaults to modules/.
              (let (configured (.ref intent-value 'root))
                (if (and (not (.ref intent-value 'root-explicit?)) (string=? configured "modules")
                         (string=? (path-strip-directory
                                   (path-strip-trailing-directory-separator (path-directory init-path))) "modules"))
                  (path-directory init-path)
                  (path-expand configured (path-directory init-path)))) input))
           (decisions (.ref intent-value 'decisions))
           (selected-values (map (lambda (row) (.ref row 'identity))
                                 (filter (lambda (row) (not (.ref row 'disabled?))) decisions)))
           (denied-values (map (lambda (row) (.ref row 'identity))
                               (filter (lambda (row) (.ref row 'disabled?)) decisions)))
           (generation-value (symbol->string (gensym 'module-directory-))))
      (def windows (and (.slot? intent-value 'windows) (.ref intent-value 'windows)))
      (def (window-root window)
        (path-expand (.ref window 'root) (path-directory init-path)))
      (def (row-window row)
        (and windows row
             (find (lambda (window) (eq? (.ref window 'mount) (.ref row 'window))) windows)))
      (def (row-root row)
        (let (window (row-window row)) (if window (window-root window) root-path)))
      (def source-owners (make-hash-table))
      (def decision-index (list->hash-table
                             (map (lambda (row) (cons (.ref row 'identity) row)) decisions)))
      ;; Index declared ownership once. Locating an imported private owner walks
      ;; path ancestors, not the module list or another filesystem search tree.
      (for-each
       (lambda (row)
         (unless (.ref row 'disabled?)
           (let* ((id (.ref row 'identity))
                  (declared (.ref row 'source-root))
                  (directory (if declared (path-expand declared (path-directory init-path))
                                 (path-expand (symbol->string id) (row-root row))))
                  (key (path-strip-trailing-directory-separator (path-normalize directory))))
             (when (hash-key? source-owners key)
               (error "duplicate declared module source owner" id directory init-path))
             (hash-put! source-owners key (.o identity: id root: key))))) decisions)
      (def (source-owner path)
        (let loop ((directory (path-strip-trailing-directory-separator
                               (path-directory (path-normalize path)))))
          (or (hash-get source-owners directory)
              (let (parent (path-strip-trailing-directory-separator (path-directory directory)))
                (and (not (equal? parent directory)) (loop parent))))))
      (def source-tree
        (.o locate-owner: source-owner
            contains-module-path?:
            (lambda (file)
              (and windows
                   (any (lambda (window)
                          (string-prefix?
                            (string-append (path-strip-trailing-directory-separator
                                             (path-normalize (window-root window))) "/")
                            (path-normalize file))) windows)))
            kernel-root:
            (let* ((collection (path-strip-trailing-directory-separator (path-normalize root-path)))
                   (parent (path-directory collection))
                   (package (path-expand "gerbil.pkg" parent)))
              ;; A nested init may explicitly select the package's modules/.
              ;; Preserve that source authority rather than treating the init's
              ;; own folder as the kernel. Do not infer an arbitrary parent.
              (if (and (string=? (path-strip-directory collection) "modules")
                       (eq? (observe! module-source-type package) 'regular))
                (begin (observe! module-source-read package) (path-normalize parent))
                (and init-path (path-normalize (path-directory init-path)))))))
      (def (locate-source id)
        (source-parts id)
        (source-cache-ref sources id
         (lambda ()
           (let* ((row (hash-get decision-index id))
                  (auto-roots
                   (if (or row (not windows)) '()
                     (filter-map
                       (lambda (window)
                         (and (eq? (.ref window 'mode) 'auto)
                              (let* ((root (window-root window))
                                     (candidate (path-expand (symbol->string id) root)))
                                (and (eq? (observe! module-source-type candidate) 'directory)
                                     (eq? (observe! module-source-type (path-expand "interface.ss" candidate)) 'regular)
                                     root)))) windows)))
                  (_unambiguous
                   (begin
                     (when (and (pair? auto-roots) (pair? (cdr auto-roots)))
                       (error "ambiguous publication identity across directory windows" id))
                     (when (and windows (not row) (null? auto-roots))
                       (error "module is outside explicit directory windows" id))))
                  (owner-root (if row (row-root row)
                                  (if (pair? auto-roots) (car auto-roots) root-path)))
                  (declared (and row (.ref row 'source-root)))
                  (origin (and declared (path-expand declared (path-directory init-path)))))
             (def (publish raw-child raw-collection-root)
               (unless (eq? (observe! module-source-type raw-child) 'directory)
                 (error "module source is not a directory" raw-child))
               (let* ((child (observe! path-normalize raw-child))
                      (collection-root (path-normalize raw-collection-root))
                      (leaf (snapshot child)))
                 (unless (.ref leaf 'interface?) (error "module has no interface.ss" id child))
                 ((.ref poo-flow-default-module-style-policy 'validate)
                  poo-flow-default-module-style-policy id child
                  (lambda (file) (observe! module-source-read file)))
                 (hash-put! source-owners (path-strip-trailing-directory-separator child)
                            (.o identity: id root: child))
                 (let (value (make-poo-flow-module-source-ref
                              'local (path-expand "interface.ss" child)
                              (list (cons 'module-id id) (cons 'module-root child)
                                    (cons 'collection-root collection-root)
                                    (cons 'source-binding (if origin 'explicit 'directory))
                                    (cons 'source-tree source-tree)
                                    (cons 'init-source init-path) (cons 'generation generation-value))))
                   (hash-put! sources id value) value)))
             ;; An explicit binding is authoritative. Never probe a local or SDK
             ;; fallback when it is absent, disabled, stale or malformed.
             (if origin
               (publish origin (path-directory (path-strip-trailing-directory-separator origin)))
               (let walk ((directory owner-root) (parts (source-parts id)))
                 (let (node (snapshot directory))
                   (unless (member (car parts) (.ref node 'child-names))
                     (error "module directory not found" id directory))
                   (let (child (path-expand (car parts) directory))
                     (if (pair? (cdr parts)) (walk child (cdr parts))
                       (publish child owner-root))))))))))
      (def (current-source? requested-generation)
        (with-catch (lambda (_exception) #f)
                    (lambda () (and (string=? requested-generation generation-value)
                                    (andmap (lambda (check) (check)) observations)))))
      (def (tree resolve directory prefix (window #f))
        (let* ((node (and (eq? (observe! module-source-type directory) 'directory) (snapshot directory)))
               (declared (filter-map
                           (lambda (id)
                             (let (text (symbol->string id))
                               (and (string-prefix? prefix text)
                                    (car (string-split (substring text (string-length prefix) (string-length text)) #\/)))))
                           (if window
                             (map (cut .ref <> 'identity)
                               (filter (lambda (row)
                                         (and (not (.ref row 'disabled?))
                                              (eq? (.ref row 'window) (.ref window 'mount)))) decisions))
                             selected-values)))
               (names (delete-duplicates/hash
                        (append (if (and node (or (not window) (eq? (.ref window 'mode) 'auto)))
                                  (.ref node 'child-names) '()) declared))))
          (object<-fun
           (lambda (key)
             (let* ((text (symbol->string key)) (child (path-expand text directory))
                    (id (string->symbol (string-append prefix text)))
                    (row (hash-get decision-index id)))
               (when (and window row (not (eq? (.ref row 'window) (.ref window 'mount))))
                 (error "publication belongs to a different directory window"
                        id (.ref window 'mount) (.ref row 'window)))
               (if (and row (.ref row 'source-root)) (resolve id)
                 (let (child-node (and (eq? (observe! module-source-type child) 'directory) (snapshot child)))
                   (if (and child-node (.ref child-node 'interface?)) (resolve id)
                     (tree resolve child (string-append (symbol->string id) "/") window))))))
           keys: (map string->symbol names))))
      ;; Capture the root metadata now, never recursively enumerate every module.
      (snapshot root-path)
      (when windows
        (for-each (lambda (window) (snapshot (window-root window))) windows))
      (.o generation: generation-value module-ids: selected-values selected: selected-values
          denied-modules: denied-values intent: intent-value init-source: init-path source-root: root-path
          locate: locate-source current?: current-source?
          eligible?: (lambda (id)
                       (let (row (hash-get decision-index id))
                         (and (not (and row (.ref row 'disabled?)))
                              (or row
                                  (if windows
                                    (any (lambda (window) (eq? (.ref window 'mode) 'auto)) windows)
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
