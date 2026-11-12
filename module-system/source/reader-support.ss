;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Source preparation identity and ordered publication read support.
(import (only-in :clan/poo/object object-construction-current?
                 call-with-current-slot-reads replay-slot-reads!)
        (only-in :clan/poo/slot-observation %call-with-recorded-slot-reads %record-slot-reads!)
        (only-in :tao3k/yuanxu/object-family/read-projection owned-read-function-scope?)
        (only-in :tao3k/yuanxu/module-system/source/preparation module-compiler-source-input-compatible?)
        (only-in :tao3k/yuanxu/module-system/source/admission current-module-source-observer
                 module-source-measure-operation module-source-measure-replay)
        (only-in :tao3k/yuanxu/module-system/source/reader-evaluation observe-reader-work))
(export (struct-out source-preparation)
        capture-source-preparation source-preparation-current? source-observation-rows
        publication-read-current require-publication-policy! publication-metadata-entry
        publication-metadata-tail publication-metadata-current call-with-publication-reads
        merge-publication-read-roots)

;; The existing preparation registry owns constructor output and its actual
;; checker identity. No successful source check or user purity tag is stored.
(defstruct source-preparation (value checker metadata path invoke public-path ready?) final: #t)
(def (capture-source-preparation value checker path ready? state)
  (make-source-preparation value checker
    state (path-normalize path) #f #f ready?))
(def (source-preparation-current? origin)
  (def (open reason)
    (module-source-measure-operation
      (list 'compiler-source-open reason (source-preparation-path origin)) void)
    #f)
  (and (or (source-preparation-checker origin) (open 'context))
       (or (if (source-preparation-value origin)
             (and (source-preparation-metadata origin) ((source-preparation-metadata origin)))
             (and (source-preparation-ready? origin) ((source-preparation-ready? origin))
                  (eq? (source-preparation-checker origin) (source-preparation-invoke origin))))
           (open 'metadata))
       (or (not (source-preparation-public-path origin))
           (module-compiler-source-input-compatible? (source-preparation-public-path origin)
                                                    (source-preparation-checker origin))
           (open 'selected))))
;; An actual input projection, not a purity label or an approval. Its runtime
;; procedure identity scopes the existing query key to this private collection.
;; Allocate in this small frame so it retains only the already-owned table.
(def (source-observation-rows observations)
  (lambda ()
    (module-source-measure-operation 'reader-source-snapshot
      (lambda () (hash->list observations)))))
;; A publication is one bounded runtime recording frame. Preserve original
;; tokens (including every external callback's suffix), but do not append the
;; same identity thousands of times to the enclosing selected-Graph getter.
;; This is an ownership projection, not a source/currentness result cache.
(def (publication-read-current reads)
  ;; Preserve the SAME projected runtime support, not an observer-side capture
  ;; of every temporary CLOS/evidence read. Keep this outside the collector's
  ;; frame so the guard cannot retain its duplicate list or token index.
  (lambda ()
    (let (observer (current-module-source-observer))
      (if (not observer)
        (module-source-measure-replay reads)
        (let (visits 0)
          ;; Count actual runtime DFS visits, not the width of the root list.
          ;; No read token or receiver is retained by this diagnostic counter.
          (def (count-prefix!)
            (replay-slot-reads! reads
              (lambda (_receiver _key) (set! visits (1+ visits)))))
          (dynamic-wind
            (lambda () (observer '(metadata-replay-start runtime) 1))
            (lambda ()
              (if (object-construction-current?)
                (with-catch
                  (lambda (cause)
                    ;; Recover the diagnostic prefix in the same synchronous
                    ;; state. No source observer runs between these checks.
                    (with-catch (lambda (_failure) (void)) count-prefix!)
                    (raise cause))
                  (lambda ()
                    (set! visits (call-with-current-slot-reads reads values))))
                (count-prefix!)))
            (lambda ()
              (observer 'metadata-replay-visits visits)
              (observer '(metadata-replay-end runtime) 1))))))))
(def (require-publication-policy! current?)
  (unless (current?) (error "stale module publication policy")))
;; Allocate checkpoints outside the admission capture's activation frame so a
;; retained publication cannot keep its temporary observed-token hash alive.
(def (publication-metadata-entry policy-current? location-current!)
  (lambda () (location-current!) (require-publication-policy! policy-current?)))
(def (publication-metadata-tail policy-current?)
  (lambda () (require-publication-policy! policy-current?)))
(def (merge-publication-read-roots groups)
  ;; Use the existing native capture's identity set. No intermediate
  ;; concatenated spine, replay, or second observer delivery is needed.
  (defvalues (_ roots)
    (%call-with-recorded-slot-reads
      (lambda () (for-each %record-slot-reads! groups))
      unique-roots?: #t))
  roots)
(def (publication-metadata-current policy-current? preparation-current!
                                   (admission-current! void) (location-current! void)
                                   (root-segments #f))
  ;; Only the fixed producer's semantic reads, plus the actual pre-role
  ;; policy identities. Preserve open producer traces without replaying Gerbil
  ;; constructor scratch reads as if they were enduring Graph requirements.
  ;; POO's topology index keys the original root spine by identity. Retain
  ;; that structure with its guard, instead of copying it at every use.
  ;; Each invocation still authenticates issuance, routes and live values.
  (def roots (and root-segments (append (car root-segments) (cdr root-segments))))
  (lambda ()
    (location-current!)
    (require-publication-policy! policy-current?)
    ;; Both replay procedures come ONLY from publication-read-current below.
    ;; With no source observer they execute the fixed runtime issued-read
    ;; checker and a void visitor; policy inspection reads runtime revisions.
    ;; Joined preflight is read-only; failure restores the original ordering.
    ;; Observers keep the full original tail even if they remove themselves.
    (let (observed? (current-module-source-observer))
      (def (split!)
        (preparation-current!)
        (if (eq? admission-current! void)
          (require-publication-policy! policy-current?)
          (begin
            (admission-current!)
            (require-publication-policy! policy-current?)
            (when observed? (preparation-current!)))))
      (if (and root-segments (not observed?) (object-construction-current?)
               (owned-read-function-scope?))
        (begin
          (with-catch
            (lambda (cause)
              ;; Restore the original first failure; a successful retry must
              ;; never turn a failed merged preflight into approval.
              (split!) (raise cause))
            (lambda ()
              (module-source-measure-replay roots)))
          (require-publication-policy! policy-current?))
        (split!)))))
(def (call-with-publication-reads action (finish #f) unique-roots?: (unique-roots? #t))
  (def failed? #f)
  (def failure #f)
  (defvalues (results reads)
    (%call-with-recorded-slot-reads
      (lambda ()
        (with-catch
          (lambda (exception) (set! failed? #t) (set! failure exception) '())
          (lambda () (call-with-values action list))))
      unique-roots?: unique-roots?))
  ;; Capture inherits the caller's observers: they ALREADY saw each real read.
  ;; Merge original tokens before any finish/diagnostic callback, preserving
  ;; the parent's native occurrence policy. Never deliver those events twice.
  ;; Partial reads also survive an action/projection failure.
  (%record-slot-reads! reads)
  (def roots
    (observe-reader-work 'reader-projection-start 'reader-projection-end
      (lambda () reads)))
  (def guarded-results
    (if (or failed? (not finish)) results
      (with-catch
        (lambda (exception) (set! failed? #t) (set! failure exception) '())
        (lambda () (finish results (publication-read-current roots) roots)))))
  (when (current-module-source-observer)
    ((current-module-source-observer)
      (list 'reader-read-roots (cons 'stored-roots (length reads))
                               (cons 'identities (length roots))) 1))
  (if failed? (raise failure) (apply values guarded-results)))
