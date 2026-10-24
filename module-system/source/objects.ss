;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Source identity is inert POO metadata. Discovery and activation belong to
;;; the consuming product, not to this Core owner.

(import (only-in :clan/poo/object .o object-revision object-protocol)
        (only-in :yuanxu/object-family/syntax defpoo-object-family))

(export yuanxu-module-source-ref-prototype
        yuanxu-module-source-ref-construction-current?
        make-yuanxu-module-source-ref
        yuanxu-module-source-ref?
        yuanxu-module-source-ref-kind
        yuanxu-module-source-ref-value
        yuanxu-module-source-ref-metadata
        make-yuanxu-module-local-source
        make-yuanxu-module-package-source
        make-yuanxu-module-standard-library-source
        make-yuanxu-module-registry-source
        make-yuanxu-module-generated-source
        yuanxu-module-source-ref=?
        yuanxu-module-source-ref->alist)

(defpoo-object-family
  (prototype yuanxu-module-source-ref-prototype
             module-source-ref?
             yuanxu-module-source-ref?)
  (constructor make-yuanxu-module-source-ref
               (kind-value kind)
               (value-value value)
               (metadata-value metadata))
  (accessors
   (yuanxu-module-source-ref-kind kind)
   (yuanxu-module-source-ref-value value)
   (yuanxu-module-source-ref-metadata metadata))
  (projections))

;; The closed directory prefix constructs this exact maintained family.
;; Capture at its definition, before exposing the prototype to contributors.
;; An edited prototype (even restored) requires the ordinary guarded path.
(def source-ref-construction-revision
  (object-revision yuanxu-module-source-ref-prototype))
(def (yuanxu-module-source-ref-construction-current?)
  (and (= source-ref-construction-revision
          (object-revision yuanxu-module-source-ref-prototype))
       (not (object-protocol yuanxu-module-source-ref-prototype))))

(def (make-yuanxu-module-local-source path)
  (make-yuanxu-module-source-ref 'local path '()))

(def (make-yuanxu-module-package-source package-name)
  (make-yuanxu-module-source-ref 'package package-name '()))

(def (make-yuanxu-module-standard-library-source module-name)
  (make-yuanxu-module-source-ref 'standard-library module-name
                                   (list (cons 'library 'standard))))

(def (make-yuanxu-module-registry-source registry-name)
  (make-yuanxu-module-source-ref 'registry registry-name '()))

(def (make-yuanxu-module-generated-source module-name)
  (make-yuanxu-module-source-ref 'generated module-name '()))

;;; Metadata records provenance, but resolver identity is kind plus value.
(def (yuanxu-module-source-ref=? left right)
  (and (eq? (yuanxu-module-source-ref-kind left)
            (yuanxu-module-source-ref-kind right))
       (equal? (yuanxu-module-source-ref-value left)
               (yuanxu-module-source-ref-value right))))

;;; Alists are produced only at an inspection boundary.
(def (yuanxu-module-source-ref->alist source-ref)
  (list (cons 'kind (yuanxu-module-source-ref-kind source-ref))
        (cons 'value (yuanxu-module-source-ref-value source-ref))
        (cons 'metadata (yuanxu-module-source-ref-metadata source-ref))))
