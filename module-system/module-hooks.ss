;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
prelude: :gerbil/core

(import (only-in :clan/poo/object .def .get .ref .o .all-slots .slot? object?))
(export ModuleHook. make-module-hooks)

;;; Named handlers describe where they run. A handler may close over an
;;; ordinary Yuanxu autoload; hook dispatch does not resolve or cache modules.
(.def ModuleHook.
  depth: 0
  .when: (lambda (_facts) #t))

(defstruct hook-entry (depth index events condition handler) final: #t)

(def (admit-hook name hook index)
  (unless (and (object? hook) (andmap (cut .slot? hook <>) '(on depth .when .run))
               (pair? (.get hook on)) (list? (.get hook on))
               (andmap symbol? (.get hook on))
               (exact-integer? (.get hook depth))
               (procedure? (.get hook .when)) (procedure? (.get hook .run)))
    (error "invalid module hook" name))
  ;; Snapshot the declaration so later POO edits require a new plan.
  (make-hook-entry (.get hook depth) index (append (.get hook on) '())
                   (.get hook .when) (.get hook .run)))

(def (hook-before? left right)
  (using ((left :- hook-entry)
          (right :- hook-entry))
    (let ((left-depth left.depth) (right-depth right.depth))
      (or (< left-depth right-depth)
          (and (= left-depth right-depth)
               (< left.index right.index))))))

(def (make-module-hooks declarations)
  (unless (object? declarations) (error "module hooks require named POO slots"))
  (let* ((names (.all-slots declarations))
         (ordered (list-sort hook-before?
                    (map (lambda (name index) (admit-hook name (.ref declarations name) index))
                         names (iota (length names))))))
    (.o .run:
        (lambda (event facts initial)
          (unless (symbol? event) (error "module hook event must be a symbol" event))
          (foldl (lambda (entry result)
                   (using (entry :- hook-entry)
                     (let ((cond-fn entry.condition)
                           (run-fn entry.handler))
                       (if (and (memq event entry.events)
                                (cond-fn facts))
                         (run-fn facts result)
                         result))))
                 initial ordered)))))
