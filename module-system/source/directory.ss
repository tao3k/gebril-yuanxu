;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Filesystem source preparation. No eval, compiler, dynamic import or runtime Loader.
(import (only-in :clan/poo/object .o .ref object<-fun)
        (only-in :std/list/list delete-duplicates/hash)
        (only-in :std/misc/ports read-all-as-string)
        :core/module-system/source/objects
        :core/module-system/source/init)
(export module-directory-context)
(def (source-cache-ref cache key compute)
  (if (hash-key? cache key) (hash-ref cache key) (compute)))
(def (source-name? name)
  (and (> (string-length name) 0) (not (member name '("." "..")))
       (andmap (lambda (c) (not (memv c '(#\/ #\\ #\:)))) (string->list name))))
(def (source-parts id)
  (let (parts (string-split (symbol->string id) #\/))
    (unless (and (pair? parts) (andmap source-name? parts))
      (error "invalid module directory identity" id))
    parts))
(def (source-type path)
  (with-catch (lambda (_exception) #f) (lambda () (file-info-type (file-info path #f)))))
(def (module-directory-context path publication-reader)
  (let ((observations '()) (directories (make-hash-table)) (sources (make-hash-table)))
    ;; Observations include negative lookups and immediate child names. They are
    ;; checked at the explicit publication boundary, not on every cached slot read.
    (def (observe! reader file)
      (let (value (reader file))
        (set! observations (cons (lambda () (equal? value (reader file))) observations))
        value))
    (def (read-text file)
      (unless (eq? (source-type file) 'regular) (error "module role must be a regular file" file))
      (call-with-input-file file read-all-as-string))
    (def (directory-names directory)
      (unless (eq? (source-type directory) 'directory) (error "module source is not a directory" directory))
      (list-sort string<? (directory-files directory)))
    (def (snapshot directory)
      (source-cache-ref directories directory
       (lambda ()
         (let* ((names (observe! directory-names directory))
                (children
                 (filter (lambda (name)
                           (and (source-name? name)
                                (eq? (source-type (path-expand name directory)) 'directory))) names))
                (value (.o path: directory child-names: children
                           interface?: (and (member "interface.ss" names) #t))))
           (unless (= (length children)
                      (length (delete-duplicates/hash (map string-downcase children))))
             (error "case-colliding module directories" directory children))
           ;; Refuse symlinks rather than accidentally traverse an escaping tree.
           (for-each (lambda (name)
                       (when (eq? (source-type (path-expand name directory)) 'symbolic-link)
                         (error "symlink in module source tree" directory name))) names)
           (hash-put! directories directory value)
           value))))
    (let* ((input (path-expand path))
           (init-path
            (if (eq? (source-type input) 'regular)
              (begin (unless (string=? (path-strip-directory input) "init.ss")
                       (error "expected init.ss or a module directory" input)) input)
              (let* ((inside (path-expand "init.ss" input))
                     (beside (path-expand "../init.ss" input))
                     (inside-type (observe! source-type inside))
                     (beside-type
                      (and (string=? (path-strip-directory
                                      (path-strip-trailing-directory-separator input)) "modules")
                           (observe! source-type beside))))
                (cond
                 ((and inside-type beside-type)
                  (error "ambiguous init.ss authority; pass the exact init path" inside beside))
                 (inside-type inside)
                 (beside-type beside)
                 (else #f)))))
           (intent-value (if init-path
                     (module-init-intent
                      (call-with-input-string (observe! read-text init-path) read-all) init-path)
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
      (def (locate-source id)
        (source-cache-ref sources id
         (lambda ()
           (let walk ((directory root-path) (parts (source-parts id)))
             (let (node (snapshot directory))
               (unless (member (car parts) (.ref node 'child-names))
                 (error "module directory not found" id directory))
               (let (child (path-expand (car parts) directory))
                 (if (pair? (cdr parts)) (walk child (cdr parts))
                   (let ((leaf (snapshot child)) (roles '("types.ss" "objects.ss" "config.ss" "interface.ss")))
                     (unless (.ref leaf 'interface?) (error "module has no interface.ss" id child))
                     (for-each (lambda (role) (observe! read-text (path-expand role child))) roles)
                     (let (value (make-poo-flow-module-source-ref
                                  'local (path-expand "interface.ss" child)
                                  (list (cons 'module-id id) (cons 'module-root child)
                                        (cons 'init-source init-path) (cons 'generation generation-value))))
                       (hash-put! sources id value) value)))))))))
      (def (current-source? requested-generation)
        (with-catch (lambda (_exception) #f)
                    (lambda () (and (string=? requested-generation generation-value)
                                    (andmap (lambda (check) (check)) observations)))))
      (def (tree resolve directory prefix)
        (let (node (snapshot directory))
          (object<-fun
           (lambda (key)
             (let* ((text (symbol->string key)) (child (path-expand text directory))
                    (id (string->symbol (string-append prefix text))) (child-node (snapshot child)))
               (if (.ref child-node 'interface?) (resolve id)
                 (tree resolve child (string-append (symbol->string id) "/")))))
           keys: (map string->symbol (.ref node 'child-names)))))
      ;; Capture the root metadata now, never recursively enumerate every module.
      (snapshot root-path)
      (.o generation: generation-value module-ids: selected-values selected: selected-values
          denied-modules: denied-values intent: intent-value init-source: init-path source-root: root-path
          locate: locate-source current?: current-source?
          eligible?: (lambda (id) (locate-source id) #t)
          namespace:
          (lambda (resolve)
            (if (eq? (.ref intent-value 'mode) 'auto)
              (tree resolve root-path "")
              #f))
          read-publication:
          (or publication-reader
              (lambda (source) (error "no source publication reader supplied; runtime Loader is not connected" source)))))))
