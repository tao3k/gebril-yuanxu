;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Serial owner qualification, NOT a filesystem transaction or deployment API.
(import :clan/poo/object)
(export serial-publication-owner)

(def (serial-publication-owner publication graph initial)
  (def revision 0)
  (def live-head initial)
  (def live-graph graph)
  (def issued '())
  (def (prepare-publication candidate)
    ;; Capture BEFORE admission, so an admission callback cannot bless a newer head.
    (def expected revision)
    (def previous live-head)
    (unless (eq? live-graph graph) (error "publication belongs to previous selection"))
    (defvalues (receipt next failure) (.call publication .publish previous candidate))
    (when failure (raise failure))
    (unless (.get receipt accepted?) (error "configuration admission refused"))
    (def plan (.get next plan))
    (def token (.o))
    ;; Payload is issuer-owned, not fields read from a caller-controlled token.
    (set! issued (cons (cons token (vector expected previous next plan graph)) issued))
    token)
  (def (commit-publication token)
    (def entry (assq token issued))
    (unless entry (error "unknown publication"))
    (def row (cdr entry))
    ;; No callback, field demand, file read, or yield in comparison/transition.
    ;; Atomic ONLY under the stated single serial owner scheduling premise.
    (unless (and (= revision (vector-ref row 0))
                 (eq? live-head (vector-ref row 1))
                 (eq? live-graph (vector-ref row 4)))
      (error "selected deployment revision changed"))
    (set! live-head (vector-ref row 2))
    (set! revision (+ revision 1))
    ;; Advancing revision also makes every token from the old epoch unusable.
    (vector-ref row 3))
  (.o prepare: prepare-publication commit: commit-publication
      ;; Test-only writer: all authorized head changes advance the revision.
      replace-head: (lambda (value) (set! live-head value) (set! revision (+ revision 1)))
      replace-selection: (lambda (value)
                           (set! live-graph value) (set! revision (+ revision 1)))
      head: (lambda () live-head)))
