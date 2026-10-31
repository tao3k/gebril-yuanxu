;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; An immutable ordered Module Catalog of constructed POO Modules. Lookup
;;; observes SourceRef identity only; it never loads or activates a source.

(import (only-in :clan/poo/object .cc .get)
        (only-in :clan/poo/mop validate)
        (only-in :std/list/list find)
        "types.ss"
        :yuanxu/module-system/source/objects)

(export ModuleSourceBinding ModuleCatalog
        yuanxu-module-catalog-entry->alist
        yuanxu-module-catalog-source-refs
        yuanxu-module-catalog-modules
        yuanxu-module-catalog-add
        yuanxu-module-catalog-find-source
        resolve-yuanxu-module-source/default
        yuanxu-module-catalog->alist)

(def (yuanxu-module-catalog-entry->alist entry)
  (list
   (cons 'source
         (yuanxu-module-source-ref->alist
          (.get entry source)))
   (cons 'module
         (.get entry module name))))

(def (yuanxu-module-catalog-source-refs catalog)
  (map (cut .get <> source) (.get catalog entries)))

(def (yuanxu-module-catalog-modules catalog)
  (map (cut .get <> module) (.get catalog entries)))

(def (yuanxu-module-catalog-add catalog entry)
  (validate ModuleCatalog
    (.cc catalog entries: (append (.get catalog entries) (list entry)))))

;;; First matching SourceRef wins; metadata does not affect identity.
(def (yuanxu-module-catalog-find-source catalog source-ref)
  (find (lambda (entry)
          (yuanxu-module-source-ref=? (.get entry source) source-ref))
        (.get catalog entries)))

(def (resolve-yuanxu-module-source/default catalog source-ref default)
  (let (entry (yuanxu-module-catalog-find-source catalog source-ref))
    (if entry
      (.get entry module)
      default)))

(def (yuanxu-module-catalog->alist catalog)
  (list
   (cons 'name (.get catalog name))
   (cons 'entries
         (map yuanxu-module-catalog-entry->alist
              (.get catalog entries)))))
