;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Read-only lowering of the bounded init declaration, never eval/import.
(import (runtime: :clan/poo/object)
        (only-in :std/list/list any)
        (only-in :tao3k/yuanxu/module-system/source/role-forms
                 init-name? parse-module-init module-init-export-name module-interface-form?
                 module-feature-declaration?)
        (only-in :tao3k/yuanxu/module-system/selection/objects yuanxu-user-module-selection))
(export module-init-intent module-init-export-name module-interface-tags module-init-source-root
        module-init-compiler-source-roots
        module-interface-declaration?)

;; A source window reads Gerbil's installed checkout tree. Keep the package
;; base fixed after first use, as Gerbil does, without initializing its CLI or
;; creating package and output directories during source discovery.
(def native-package-root
  (delay (path-expand "pkg" (gerbil-path))))
(def (native-package-checkout package)
  (and package (path-expand package (force native-package-root))))
(def (module-init-source-root intent source-path)
  (def package (and (.slot? intent 'package) (.ref intent 'package)))
  (path-expand (.ref intent 'root)
    (or (native-package-checkout package) (path-directory source-path))))

(def (module-init-compiler-source-roots declaration source-path)
  (let-values (((windows _mounted? _test-dir) (parse-module-init (list declaration) source-path)))
    (filter-map (lambda (window)
                  (with ([_ _ _ _ _ _ package] window)
                    (native-package-checkout package)))
                windows)))

;; A filename is not a Module declaration. Native public library facades can
;; also be named interface.ss; they remain ordinary compiler import edges.
(def (module-interface-declaration? path text)
  (def forms (call-with-input-string text read-all))
  (unless (and (pair? forms) (andmap (cut module-interface-form? <> forms) forms))
    (error "invalid Interface configuration or library facade" path))
  (any (lambda (form)
         (and (eq? (car form) '.def) (not (module-feature-declaration? path form)))) forms))

;; A declaration belongs to its runtime module identity, not its prelude, Git
;; remote or the caller's filesystem spelling. init.ss is a convention, not a
;; restriction on where yuanxu! may declare a directory window.
(def (valid-tags? tags)
  (and (pair? tags) (list? tags) (andmap init-name? tags)
       (let loop ((remaining tags))
         (or (null? remaining)
             (and (not (memq (car remaining) (cdr remaining))) (loop (cdr remaining)))))))

;; Return false for an ordinary Gerbil library. Module tags are literal
;; Interface metadata, never a slot getter or an author callback.
(def (module-interface-tags path text)
  (def forms (call-with-input-string text read-all))
  (def declarations
    (filter (lambda (form)
              (and (pair? form) (eq? (car form) '.def)
                   (not (module-feature-declaration? path form)))) forms))
  (if (not (and (pair? declarations)
                (andmap (cut module-interface-form? <> forms) forms)))
    #f
    (begin
      (unless (and (null? (cdr declarations)) (pair? (cdar declarations)))
        (error "invalid profiled Module Interface" path))
      (let ((fields (cddar declarations)) (tags #f))
        (let walk ((tail fields))
          (cond
           ((null? tail)
            (unless tags (error "profiled Module Interface requires literal tags:" path))
            tags)
           ((eq? (car tail) 'tags:)
            (match (cdr tail)
              ([['quote value] . rest]
               (unless (and (not tags) (valid-tags? value))
                 (error "invalid or duplicate Interface tags:" path))
               (set! tags value)
               (walk rest))
              (_ (error "Interface tags: must be a quoted list of symbols" path))))
           ((and (keyword? (car tail)) (pair? (cdr tail))) (walk (cddr tail)))
           (else (walk (cdr tail)))))))))

(def (module-init-intent forms source-path)
  (def (decision row)
    (with ([identity group module flags disabled? disable-specified? source-root] row)
      (.o identity disabled? disable-specified? source-root
          selection: (.+ (yuanxu-user-module-selection group module flags)
                          (.o enabled?: (not disabled?))))))
  (def (intent window)
    (with ([mode root mount profile root-explicit? rows package] window)
      (.o mode root mount profile root-explicit? package init-source: source-path
          decisions: (map decision rows))))
  (let-values (((windows mounted? test-directory) (parse-module-init forms source-path)))
    (def intents (map intent windows))
    (if mounted?
      (.o mode: (if (any (lambda (window) (eq? (.ref window 'mode) 'auto)) intents)
                  'auto 'explicit)
          root: (.ref (car intents) 'root) root-explicit?: #t init-source: source-path
          windows: intents test-dir: test-directory
          decisions: (foldr append '()
                       (map (lambda (window)
                              (def name (.ref window 'mount))
                              (map (lambda (row) (.+ row (.o window: name)))
                                   (.ref window 'decisions))) intents)))
      (.cc (car intents) 'test-dir test-directory))))
