;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Source-neutral, ordered POO collection composition. Filesystem discovery,
;;; source admission, and module role policy belong to the consuming product.

(import (only-in :clan/poo/object .o .ref .slot? object?)
        (only-in :std/list/list any every))

(export yuanxu-module-source-collection-prototype
        yuanxu-module-source-collection?
        yuanxu-module-source-collection-identity
        yuanxu-module-source-collection-locate
        yuanxu-module-load-path-prototype
        make-yuanxu-module-load-path
        extend-yuanxu-module-load-path
        yuanxu-module-load-path?
        yuanxu-module-load-path-identity
        yuanxu-module-load-path-collections
        yuanxu-module-load-path-locate)

(def yuanxu-module-source-collection-prototype
  (.o (module-source-collection? #t)))

(def (yuanxu-module-source-collection? value)
  (and (object? value)
       (.slot? value 'module-source-collection?)
       (.ref value 'module-source-collection?)
       (.slot? value 'identity)
       (symbol? (.ref value 'identity))
       (.slot? value 'locate)
       (procedure? (.ref value 'locate))))

(def (yuanxu-module-source-collection-identity collection)
  (.ref collection 'identity))

(def (yuanxu-module-source-collection-locate collection module-key)
  ((.ref collection 'locate) collection module-key '(interface)))

(def yuanxu-module-load-path-prototype
  (.o (module-load-path? #t)))

(def (yuanxu-module-load-path? value)
  (and (object? value)
       (.slot? value 'module-load-path?)
       (.ref value 'module-load-path?)
       (.slot? value 'identity)
       (symbol? (.ref value 'identity))
       (.slot? value 'collections)
       (list? (.ref value 'collections))
       (every yuanxu-module-source-collection?
              (.ref value 'collections))))

(def (yuanxu-module-load-path-identity load-path)
  (.ref load-path 'identity))

(def (yuanxu-module-load-path-collections load-path)
  (.ref load-path 'collections))

(def (yuanxu-module-load-path-valid! load-path)
  (unless (yuanxu-module-load-path? load-path)
    (error "invalid Yuanxu module load path" load-path))
  (let ((seen (make-hash-table))
        (identities
         (map yuanxu-module-source-collection-identity
              (yuanxu-module-load-path-collections load-path))))
    (for-each
     (lambda (identity)
       (when (hash-key? seen identity)
         (error "duplicate Yuanxu module source collection" identities))
       (hash-put! seen identity #t))
     identities))
  load-path)

(def (make-yuanxu-module-load-path identity-value collections-value)
  (yuanxu-module-load-path-valid!
   (.o (:: @ yuanxu-module-load-path-prototype)
       (identity identity-value)
       (collections collections-value))))

;;; Appended collections have lower priority. No mutable global load path.
(def (extend-yuanxu-module-load-path base identity-value collections-value)
  (unless (yuanxu-module-load-path? base)
    (error "module load path extension requires a valid base" base))
  (yuanxu-module-load-path-valid!
   (.o (:: @ base)
       (identity identity-value)
       (collections
        (append (yuanxu-module-load-path-collections base)
                collections-value)))))

(def (yuanxu-module-load-path-locate load-path module-key)
  (or (any (lambda (collection)
             (let (source-refs
                   (yuanxu-module-source-collection-locate
                    collection module-key))
               (and (pair? source-refs) source-refs)))
           (yuanxu-module-load-path-collections load-path))
      '()))
