;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Shared native POO composition and constant-slot overlay algorithms.
;;; Dynamic/self/super slots remain on the native .mix path. No product catalog.
(import (only-in :clan/poo/object .o .@ .ref .mix .slot? object?
                 $constant-slot-spec object<-fun .all-slots object-slots
                 object-supers make-object $constant-slot-spec?))

(export control-plane-role
        role-name
        role-kind
        role-responsibility
        role-runtime-owner
        role-slot/default
        role-compose
        role-object?
        role-constant-slots
        role-instance-overlay-compatible?
        role-instance-overlay-defaults
        role-instance-overlay/compatible
        role-instance-overlay3/compatible
        role-instance-overlay)

(def (role-values/tail values tail)
  (append values tail))

(def control-plane-role
  (.mix
   slots:
   (list
    (cons 'name ($constant-slot-spec 'control-plane))
    (cons 'kind ($constant-slot-spec 'system))
    (cons 'responsibility ($constant-slot-spec 'conceptual-model))
    (cons 'runtime-owner ($constant-slot-spec 'gerbil))
    (cons 'control-plane-capability
          ($constant-slot-spec 'conceptual-model))
    (cons 'compose
          ($constant-slot-spec
           (lambda roles
             (apply .mix
                    (role-values/tail roles (list control-plane-role)))))))))

(def (role-name role)
  (.@ role name))

(def (role-kind role)
  (.@ role kind))

(def (role-responsibility role)
  (.@ role responsibility))

(def (role-runtime-owner role)
  (.@ role runtime-owner))

(def (role-slot/default role slot default)
  (if (and (role-object? role)
           (.slot? role slot))
    (.ref role slot)
    default))

(def (role-compose . roles)
  (apply (.@ control-plane-role compose) roles))

(def (role-constant-slot-specs? slots)
  (or (null? slots)
      (and ($constant-slot-spec? (cdar slots))
           (role-constant-slot-specs? (cdr slots)))))

(def (role-instance-overlay-compatible?/seen role path)
  (and (role-object? role)
       (not (memq role path))
       (role-constant-slot-specs? (object-slots role))
       (role-instance-overlay-compatible-list?
        (object-supers role) (cons role path))))

(def (role-instance-overlay-compatible-list? roles path)
  (or (null? roles)
      (and (role-instance-overlay-compatible?/seen (car roles) path)
           (role-instance-overlay-compatible-list? (cdr roles) path))))

(def (role-instance-overlay-compatible? role)
  (role-instance-overlay-compatible?/seen role '()))

(def (role-instance-overlay-owner-index/one keys source roles owners)
  (if (null? keys)
      (role-instance-overlay-owner-index roles owners)
      (let (key (car keys))
        (if (hash-key? owners key)
            (role-instance-overlay-owner-index/one
             (cdr keys) source roles owners)
            (begin
              (hash-put! owners key source)
              (role-instance-overlay-owner-index/one
               (cdr keys) source roles owners))))))

(def (role-instance-overlay-owner-index roles owners)
  (if (or (null? roles) (null? (cdr roles)))
      owners
      (let (source (car roles))
        (role-instance-overlay-owner-index/one
         (.all-slots source) source (cdr roles) owners))))

(def (role-instance-overlay-last roles)
  (if (null? (cdr roles))
      (car roles)
      (role-instance-overlay-last (cdr roles))))

(def (role-instance-overlay-keys roles)
  (apply append (map .all-slots roles)))

(def (role-instance-overlay-resolve owners fallback slot)
  (.ref (if (hash-key? owners slot)
            (hash-ref owners slot)
            fallback)
        slot))

(def (role-instance-overlay/compatible . roles)
  (let* ((owners
          (role-instance-overlay-owner-index roles (make-hash-table)))
         (fallback (role-instance-overlay-last roles)))
    (object<-fun
     (lambda (slot)
       (role-instance-overlay-resolve owners fallback slot))
     keys: (role-instance-overlay-keys roles))))

(def (role-instance-overlay-defaults shared)
  (map (lambda (slot) (cons slot (.ref shared slot)))
       (.all-slots shared)))

(def (role-instance-overlay3/compatible marker local shared-defaults)
  (make-object
   defaults: shared-defaults
   slots: (append (object-slots local)
                  (object-slots marker))))

(def (role-instance-overlay . roles)
  (unless (and (pair? roles)
               (role-instance-overlay-compatible-list? roles '()))
    (error "role instance overlay requires constant-slot POO roles" roles))
  (apply role-instance-overlay/compatible roles))

(def (role-object? role)
  (object? role))

(def (role-constant-slots/rev alist slots-rev)
  (if (null? alist)
    slots-rev
    (role-constant-slots/rev
     (cdr alist)
     (cons (cons (caar alist) ($constant-slot-spec (cdar alist)))
           slots-rev))))

(def (role-constant-slots alist)
  (reverse (role-constant-slots/rev alist '())))
