;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An immutable ordered Module Catalog of constructed POO Modules. Lookup
;;; observes SourceRef identity only; it never loads or activates a source.

(import (only-in :clan/poo/object .ref)
        (only-in :yuanxu/object-family/syntax defpoo-object-family)
        :yuanxu/module-system/source/objects)

(export yuanxu-module-catalog-entry-prototype
        make-yuanxu-module-catalog-entry
        yuanxu-module-catalog-entry?
        yuanxu-module-catalog-entry-source
        yuanxu-module-catalog-entry-module
        yuanxu-module-catalog-entry->alist
        yuanxu-module-catalog-prototype
        make-yuanxu-module-catalog
        yuanxu-module-catalog?
        yuanxu-module-catalog-name
        yuanxu-module-catalog-entries
        yuanxu-module-catalog-source-refs
        yuanxu-module-catalog-modules
        yuanxu-module-catalog-add
        yuanxu-module-catalog-find-source
        resolve-yuanxu-module-source/default
        yuanxu-module-catalog->alist)

(defpoo-object-family
  (prototype yuanxu-module-catalog-entry-prototype
             catalog-entry?
             yuanxu-module-catalog-entry?)
  (constructor make-yuanxu-module-catalog-entry
               (source-value source)
               (module-value module))
  (accessors
   (yuanxu-module-catalog-entry-source source)
   (yuanxu-module-catalog-entry-module module))
  (projections))

(def (yuanxu-module-catalog-entry->alist entry)
  (list
   (cons 'source
         (yuanxu-module-source-ref->alist
          (yuanxu-module-catalog-entry-source entry)))
   (cons 'module
         (.ref (yuanxu-module-catalog-entry-module entry) 'name))))

(defpoo-object-family
  (prototype yuanxu-module-catalog-prototype
             catalog?
             yuanxu-module-catalog?)
  (constructor make-yuanxu-module-catalog
               (name-value name)
               (entries-value entries))
  (accessors
   (yuanxu-module-catalog-name name)
   (yuanxu-module-catalog-entries entries))
  (projections))

(def (yuanxu-module-catalog-source-refs catalog)
  (map yuanxu-module-catalog-entry-source
       (yuanxu-module-catalog-entries catalog)))

(def (yuanxu-module-catalog-modules catalog)
  (map yuanxu-module-catalog-entry-module
       (yuanxu-module-catalog-entries catalog)))

(def (yuanxu-module-catalog-add catalog entry)
  (make-yuanxu-module-catalog
   (yuanxu-module-catalog-name catalog)
   (append (yuanxu-module-catalog-entries catalog)
           (list entry))))

;;; First matching SourceRef wins; metadata does not affect identity.
(def (module-catalog-find-source-in entries source-ref)
  (cond
   ((null? entries) #f)
   ((yuanxu-module-source-ref=?
     (yuanxu-module-catalog-entry-source (car entries))
     source-ref)
    (car entries))
   (else
    (module-catalog-find-source-in (cdr entries) source-ref))))

(def (yuanxu-module-catalog-find-source catalog source-ref)
  (module-catalog-find-source-in
   (yuanxu-module-catalog-entries catalog)
   source-ref))

(def (resolve-yuanxu-module-source/default catalog source-ref default)
  (let (entry (yuanxu-module-catalog-find-source catalog source-ref))
    (if entry
      (yuanxu-module-catalog-entry-module entry)
      default)))

(def (yuanxu-module-catalog->alist catalog)
  (list
   (cons 'name (yuanxu-module-catalog-name catalog))
   (cons 'entries
         (map yuanxu-module-catalog-entry->alist
              (yuanxu-module-catalog-entries catalog)))))
