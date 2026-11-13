;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Assemble the public reader over one generation-local source session.
(import (only-in :clan/poo/object .o .ref object-construction-current?)
        (only-in :tao3k/yuanxu/object-family/read-projection current-owned-read-open-guard
                 call-with-owned-source-reads owned-read-function-scope?)
        (only-in :tao3k/yuanxu/module-system/source/directory
                 directory-candidate-guard? directory-candidate-guard-invoke)
        (only-in :tao3k/yuanxu/module-system/source/observations module-source-measure-replay)
        (only-in :tao3k/yuanxu/module-system/source/publication module-publication-contract-current?)
        :tao3k/yuanxu/module-system/source/admission
        :tao3k/yuanxu/module-system/source/objects
        :tao3k/yuanxu/module-system/source/reader-session
        :tao3k/yuanxu/module-system/source/reader-support
        :tao3k/yuanxu/module-system/source/reader-preparation
        :tao3k/yuanxu/module-system/source/reader-guards
        :tao3k/yuanxu/module-system/source/reader-evaluation
        :tao3k/yuanxu/module-system/source/configuration-reader
        :tao3k/yuanxu/module-system/source/publication-reader)
(export module-publication-reader module-prepared-source-binding call-with-publication-reads)

(def (module-publication-reader (previous-context #f))
  (def session (new-reader-session previous-context))
  ;; These are the original per-reader checker identities. Pure-query keys and
  ;; the active owned-read handler must retain the same procedure at each use.
  (set! (reader-session-check-current session) (cut reader-check-current! session <...>))
  (set! (reader-session-check-current/closed session) (cut reader-check-current/closed! session <...>))
  (set! (reader-session-open-boundary session) (cut reader-open-boundary! session <...>))
  (.o .fork:
      (lambda ()
        (module-publication-reader
          (reader-role-transfer
            (reader-session-kernel-contexts session)
            (reader-session-kernel-inputs session)
            (reader-session-kernel-owners session)
            (reader-session-kernel-data session)
            (reader-session-kernel-initializers session)
            (reader-session-compiler-contexts session))))
      read: (lambda (source) (call-with-publication-reads (cut reader-read-publication session source)))
      ;; Internal paired-directory continuation, not an author callback API.
      read-located:
      (lambda (prefix)
        (call-with-publication-reads
          (lambda ()
            (reader-read-publication session #f prefix values))))
      ;; Same preparation index as ordinary reads. Discovery is inert; the
      ;; producer below executes runtime roles and actual admission on demand.
      discover:
      (lambda (source)
        (reader-full-current! session)
        (let (prepared (reader-prepare-publication session source))
          (reader-full-current! session) prepared))
      read-candidate:
      (lambda (prefix expected-id context-value (epoch-current #f) (location void))
        (def directory-location? (directory-candidate-guard? location))
        (def location-current!
          (if directory-location? (directory-candidate-guard-invoke location) location))
        (def tools (list->hash-table (reader-session-interpreter-observations session)))
        (def scope (make-candidate-support '() tools (source-observation-rows tools)
                      #f epoch-current location-current!))
        (with-catch
          (lambda (failure) (set! (reader-session-refused? session) #t) (raise failure))
          (lambda ()
            (call-with-publication-reads
              (lambda ()
                (parameterize (((reader-session-candidate session) scope)
                               (current-owned-read-open-guard (reader-session-open-boundary session)))
                  (call-with-owned-source-reads (reader-session-open-boundary session)
                    (lambda ()
                      (unless (module-source-style-policy-current?) (reader-open-boundary! session))
                      (def policy-current? (module-source-publication-policy))
                      (def preparation-current! void)
                      (def preparation-roots '())
                      (def fused-entry? #f)
                      ;; Discovery is inert. Roles run later in the SAME
                      ;; reader/preparation index, before actual admission.
                      (def source
                        (observe-reader-work 'reader-location-start 'reader-location-end prefix))
                      (def prepared
                        (observe-reader-work 'reader-preparation-start 'reader-preparation-end
                          (lambda ()
                            (call-with-publication-reads
                              (lambda () (reader-prepare-publication session source))
                              (lambda (results preparation-check! roots)
                                (set! fused-entry?
                                  (and directory-location? (not (candidate-support-open? scope))
                                       (not (current-module-source-observer))
                                       (object-construction-current?) (owned-read-function-scope?)))
                                (unless fused-entry?
                                  (module-source-measure-operation 'reader-preparation-replay preparation-check!))
                                (set! preparation-current! preparation-check!)
                                (set! preparation-roots roots)
                                results)))))
                      (def check-prepared!
                        (publication-metadata-current policy-current? preparation-current! void location-current!))
                      (def (check-candidate!)
                        (module-source-measure-operation 'reader-candidate-checkpoint-replay check-prepared!))
                      (set! (candidate-support-metadata-current scope)
                        (if fused-entry?
                          (lambda ()
                            ;; Reader's first declaration-before guard runs
                            ;; before any author/MOP or native expansion call.
                            ;; Reinstall the ordinary independent checkpoint
                            ;; before executing the native protected entry.
                            (set! (candidate-support-metadata-current scope) check-candidate!)
                            (module-source-measure-operation 'reader-candidate-entry-replay
                              (lambda ()
                                (module-source-measure-replay preparation-roots
                                  (publication-metadata-entry policy-current? location-current!))
                                (require-publication-policy! policy-current?))))
                          check-candidate!))
                      (when (current-module-source-observer)
                        ((current-module-source-observer) 'publication-discovered 1))
                      (reader-read-publication session source #f
                        (lambda (source value owners)
                          (require-publication-policy! policy-current?)
                          (unless (module-publication-contract-current?) (reader-open-boundary! session))
                          (def fused-return? #f)
                          (def (check-admitted! (metadata? #t))
                            (parameterize ((current-module-source-phase 'candidate-admitted))
                              (reader-current! session #f metadata?)))
                          ;; Keep the interpreter's original observation bundle,
                          ;; but issue admission support from this fixed producer
                          ;; boundary, after role initialization has completed.
                          (call-with-publication-reads
                            (lambda ()
                              (def evidence
                                (observe-reader-work 'reader-admission-start 'reader-admission-end
                                  (lambda ()
                                    (admit-module-publication! source expected-id value context-value))))
                              (def checked (.ref evidence 'candidate))
                              (set! fused-return?
                                (and fused-entry? (not (current-module-source-observer))
                                     (object-construction-current?) (owned-read-function-scope?)
                                     (reader-fixed-candidate-guards? scope)))
                              (unless fused-return? (check-admitted!))
                              (list source checked evidence))
                            (lambda (results admission-current! roots)
                              ;; Aggregate projection keeps the original segments.
                              ;; The closed return and its guard share one ordered
                              ;; spine. Observed candidates already replay the two
                              ;; original sequences and need no additional copy.
                              (def root-segments (cons preparation-roots roots))
                              (def publication-roots
                                (and (or fused-return? (not (current-module-source-observer)))
                                     (append preparation-roots roots)))
                              (def guard
                                (publication-metadata-current policy-current? preparation-current! admission-current! location-current!
                                  publication-roots))
                              (def entry! (publication-metadata-entry policy-current? location-current!))
                              (def tail! (publication-metadata-tail policy-current?))
                              (module-source-measure-operation 'reader-candidate-return-replay
                                (if fused-return?
                                  (lambda ()
                                    (def entered? #f)
                                    (def completed? #f)
                                    (call-with-module-source-read-cache
                                      (lambda ()
                                        (entry!)
                                        (with-catch
                                          (lambda (cause)
                                            ;; Recover the original source refusal in
                                            ;; an independent window after a replay refusal.
                                            (call-with-module-source-fresh-reads
                                              (lambda ()
                                                (unless entered?
                                                  (check-admitted!))
                                                (when (or (not entered?) completed?) (guard))))
                                            (raise cause))
                                          (lambda ()
                                            ;; The fixed directory and source checks
                                            ;; share one observation window around native
                                            ;; replay. Open candidates use the guard below.
                                            (module-source-measure-operation 'reader-candidate-fused-return-replay
                                              (lambda ()
                                                (module-source-measure-replay publication-roots
                                                  (lambda ()
                                                    (set! entered? #t)
                                                    (tail!)
                                                    (check-admitted! #f)
                                                    (entry!)
                                                    (set! completed? #t)))))))
                                        (tail!))))
                                  guard))
                              ;; Fixed source-only checkpoints and ORIGINAL
                              ;; issued roots for the linker's POO topology
                              ;; slot. No successful check or purity flag.
                              (list (append (car results)
                                      (list owners guard entry! tail! root-segments)))))) prepared))
                    )))))))
      admit-current: (cut reader-full-current! session <...>)
      read-only-current?: (cut reader-source-state-current? session <...>)
      metadata-state: (cut reader-bind-input-state session <...>)
      preparation:
      (lambda (source)
        ;; Only a successfully observed declaration may supply this capability.
        ;; This is the same inert projection, not another publication reader.
        (reader-current! session)
        (unless (hash-key? (reader-session-dependencies session) (path-normalize (yuanxu-module-source-ref-value source)))
          (error "publication preparation requires a completed read"))
        (let (prepared (hash-get (reader-session-preparations session) (reader-preparation-key session source)))
          (unless prepared (error "publication preparation owner mismatch"))
          (reader-check-preparation-policy! session prepared)
          ;; Take the dependency registry at this consumption, not when the
          ;; inert preparation was cached. Both views share this one guard.
          (reader-derived-input session prepared source
            (hash-ref (reader-session-dependencies session) (path-normalize (yuanxu-module-source-ref-value source))))))
      inputs: (lambda (source)
                (parameterize ((current-module-source-phase 'publication-inputs)) (reader-current! session))
                (hash-ref (reader-session-dependencies session) (path-normalize (yuanxu-module-source-ref-value source))))))
