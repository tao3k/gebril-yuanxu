;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Authenticate source, metadata and policy at reader operation boundaries.
(import (only-in :clan/poo/read-projection current-owned-read-open-guard owned-read-function-scope?)
        :tao3k/yuanxu/module-system/source/admission
        :tao3k/yuanxu/module-system/source/reader-session
        :tao3k/yuanxu/module-system/source/reader-support
        (only-in :tao3k/yuanxu/module-system/source/import-provenance compiler-context-origin-current?))
(export reader-check-tool-contexts! reader-check-current! reader-check-current/closed!
        reader-current! reader-full-current! reader-open-boundary! reader-fixed-candidate-guards?)

(def (reader-check-tool-contexts! session)
  (module-source-measure-operation 'reader-native-identity
   (lambda ()
    (hash-for-each
      (lambda (context origin)
        (unless (compiler-context-origin-current? context origin)
          (error "compiler tool context changed; use a fresh publication reader")))
      (reader-session-compiler-contexts session)))))
(def (reader-check-current! session observed-guards observations)
  (when (current-module-source-observer)
    ((current-module-source-observer) '(publication-guard-run) 1))
  ;; Loaded prerequisites retain native code provenance, not a checkout
  ;; byte dependency. Revalidate the captured native bindings on EVERY
  ;; boundary; this is not a remembered successful admission.
  (reader-check-tool-contexts! session)
  (module-source-measure-operation 'reader-tool-source-current
    (lambda ()
      (module-source-admit-current! observations
                                    "compiler tool source changed; use a fresh reader")))
  (module-source-measure-operation 'reader-source-guards
    (lambda ()
      (for-each (lambda (guard) (module-source-observe (source-preparation-invoke guard))) observed-guards))))
(def (reader-check-current/closed! session inputs _guard-count _source-count)
  ;; record-source-observations! only adds paths or verifies an equal
  ;; existing revision. With its private owner identity and cardinality,
  ;; the same bounded query denotes the same source snapshot. Materialize
  ;; rows only on a query miss; never hash every source's full text just
  ;; to discover that this pure check already ran in the current window.
  ;; Guard spines also grow only by cons. Their payloads include source
  ;; snapshots and POO objects: keep them OUT of the structural query key.
  ;; The private producer identifies the support owner; counts distinguish
  ;; each growing support generation inside this same observation window.
  (let* ((scope ((reader-session-candidate session)))
         (local? (and scope (not (candidate-support-open? scope)))))
    (reader-check-current! session (if local? (candidate-support-guards scope) (reader-session-guards session)) (inputs))))
(def (reader-fixed-candidate-guards? candidate)
  (and (not (candidate-support-open? candidate))
       (with-catch (lambda (_changed) #f)
         (lambda ()
           (andmap
             (lambda (guard)
               (let (ready? (source-preparation-ready? guard))
                 (and ready? (source-preparation-checker guard)
                      (eq? (source-preparation-checker guard) (source-preparation-invoke guard))
                      (ready?))))
             (candidate-support-guards candidate))))))
(def (reader-current! session (replay-site #f) (metadata? #t))
  (when (reader-session-refused? session) (error "build publication reader was refused"))
  ;; Only a private, unpublished candidate may use operation support.
  ;; Public reader uses and open callbacks retain the whole observed epoch.
  ;; Recheck bytes/package observations once per reader boundary; repeatedly
  ;; reparsing every tool through every individual guard is quadratic work.
  (def (check!)
    (when (and ((reader-session-candidate session)) (current-module-source-observer))
      ((current-module-source-observer)
        (if (candidate-support-open? ((reader-session-candidate session)))
          'candidate-open-guard 'candidate-local-guard) 1))
    ;; Metadata replay belongs to this SAME observed guard interval.
    ;; Keep it inside the existing brackets, not in an unattributed gap.
    (when (and metadata? ((reader-session-candidate session)))
      (module-source-measure-operation
        (list 'reader-candidate-replay-site (or replay-site (current-module-source-phase)))
        (candidate-support-metadata-current ((reader-session-candidate session)))))
    (parameterize ((current-module-source-phase 'publication-current))
      (call-with-module-source-read-cache
       (lambda ()
         ;; A nested Graph/role guard can reach this reader many times in the
         ;; same pure check. Memoize that check, including byte comparisons,
         ;; only until the enclosing observation boundary ends. A newly added
         ;; source guard changes the key, even within that boundary.
         (let* ((scope ((reader-session-candidate session)))
                (local? (and scope (not (candidate-support-open? scope))))
                (selected-guards (if local? (candidate-support-guards scope) (reader-session-guards session)))
                (tools (if local? (candidate-support-tools scope) (reader-session-tool-observations session))))
           (if (current-module-source-observer)
             ;; Open observers keep the original snapshot/callback order.
             (module-source-observe (reader-session-check-current session) selected-guards
               ((if local? (candidate-support-tool-rows scope) (reader-session-tool-rows session))))
             (module-source-observe (reader-session-check-current/closed session)
               (if local? (candidate-support-tool-rows scope) (reader-session-tool-rows session))
               (if local? (length selected-guards) (reader-session-guard-count session))
               (hash-length tools))))))))
  ;; Attribute the caller without changing the cache key or retaining a
  ;; result across its boundary. Brackets also close on a refused check.
  (let ((observer (current-module-source-observer))
        (origin (current-module-source-phase)))
    (begin0
      (if observer
        (dynamic-wind
          (lambda () (observer (list 'publication-guard-start origin) 1))
          check!
          (lambda () (observer (list 'publication-guard-end origin) 1)))
        (module-source-measure-operation 'reader-current
          (lambda ()
            (module-source-measure-operation (list 'reader-current origin)
              (lambda ()
                (let (candidate ((reader-session-candidate session)))
                  (if (and candidate (not (candidate-support-open? candidate))
                           (candidate-support-directory-location? candidate)
                           (owned-read-function-scope?) (object-construction-current?)
                           (reader-fixed-candidate-guards? candidate))
                    ;; Directory and prepared-input checks observe the same
                    ;; bytes in this closed checkpoint. The caller still ends
                    ;; the window before expansion, initialization or admission.
                    (call-with-module-source-read-cache check!)
                    (check!))))))))
      ;; Open observers (including one which removes itself), public checks
      ;; and open candidate callbacks may alter native metadata. No verdict
      ;; crosses their return. A closed candidate's fixed source checks have
      ;; no such effect; retain its existing pure observation window.
      (when (or observer (not ((reader-session-candidate session))) (candidate-support-open? ((reader-session-candidate session))))
        (reader-check-tool-contexts! session)))))
(def (reader-full-current! session)
  (parameterize (((reader-session-candidate session) #f) (current-owned-read-open-guard #f)) (reader-current! session)))
(def (reader-open-boundary! session (reason (current-module-source-phase)))
  (module-source-measure-operation
    (list 'reader-open-boundary (if (pair? reason) (car reason) reason))
    void)
  (when ((reader-session-candidate session)) ((candidate-support-metadata-current ((reader-session-candidate session)))))
  (when (and ((reader-session-candidate session)) (not (candidate-support-open? ((reader-session-candidate session))))
             (current-module-source-observer))
    ((current-module-source-observer)
      (list 'candidate-open-boundary reason) 1))
  (when ((reader-session-candidate session)) (set! (candidate-support-open? ((reader-session-candidate session))) #t))
  (let (epoch (and ((reader-session-candidate session)) (candidate-support-epoch-current ((reader-session-candidate session)))))
    (parameterize (((reader-session-candidate session) #f) (current-owned-read-open-guard #f))
      (if epoch (epoch) (reader-current! session)))))
