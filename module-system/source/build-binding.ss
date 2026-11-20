;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; The Build value is accessible only while projecting standard Make inputs.
(import (only-in :clan/poo/object .o .ref)
        (only-in :tao3k/yuanxu/module-system/source/selection module-selected-feature?))
(export define-module-build-binding current-module-build-phase? current-module-build-resolver
        current-module-ffi-build current-module-build-selection module-build-feature-selected?)

;; The package build entry supplies the native compiler action for this invocation.
(def current-module-ffi-build (make-parameter #f))

;; Internal phase capability, not a runtime Loader or a global binding registry.
(def current-module-build-phase? (make-parameter #f))
(def current-module-build-selection (make-parameter #f))

;; Build callbacks read facts from the active compiler selection.
(def (module-build-feature-selected? leaf feature)
  (def graph (current-module-build-selection))
  (unless graph
    (error "Feature decision requires an admitted build selection" leaf feature))
  (module-selected-feature? graph leaf feature))

(def current-module-build-resolver (make-parameter #f))
(def (module-build-binding-value state)
  ;; Check outside the cached slot: a previously forced Build is still forbidden
  ;; to ordinary config/runtime consumers.
  (unless (current-module-build-phase?)
    (error "Build is available only in the Module build-publication phase"))
  (.ref state 'value))
(defsyntax (define-module-build-binding stx)
  (syntax-case stx ()
    ((_ name)
     (identifier? #'name)
     (with-syntax ((resolver (genident 'build-resolver))
                   (state (genident 'build-state)))
       #'(begin
           (def resolver (current-module-build-resolver))
           (def state
             (.o value:
               (if resolver (resolver)
                   (error "Module Build has no admitted build resolver"))))
           (defsyntax name
             (identifier-rules ()
               ((_ . args) ((module-build-binding-value state) . args))
               (_ (module-build-binding-value state)))))))
    (_ (raise-syntax-error #f "expected an internal Build binding" stx))))
