;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Construction is not admission. Public constructors retain their boundary.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :clan/poo/slot-observation
                 %call-with-recorded-slot-reads slot-read-key slot-read-dependencies
                 slot-read-receiver call-with-slot-read-observer)
        (only-in "./module-candidate-stage-test" with-other-source)
        (only-in "./module-publication-test" write-file)
        (only-in :core/module-system/source/admission poo-flow-module-style-policy-prototype)
        (only-in :core/module-system/source/interface poo-flow-module-interface)
        (only-in :core/module-system/types ModuleAuthoringProfileContract)
        (only-in :core/module-system/authoring/roles poo-flow-default-module-authoring-profile)
        (only-in :core/observability/testing-case poo-flow-test-case))
(export module-authoring-stage-test)

(def (stale-native-dependency? failure)
  (and (Error? failure) (string=? (Error-message failure) "stale slot dependency")))

;; Read original tokens without forcing any new slot. Structural bootstrap and
;; inherited lookup dependencies MUST remain; only constructor receipts vanish.
(def (constructor-receipt? roots)
  (def seen (make-hash-table-eq))
  (def (visit read)
    (and (not (hash-key? seen read))
         (begin
           (hash-put! seen read #t)
           (let* ((receiver (slot-read-receiver read))
                  (instance (and (object? receiver) (object-%instance receiver)))
                  (kind (and instance (hash-get instance 'kind))))
             (or (memq kind '(poo-flow.type.classification-evidence
                              poo-flow.contract.validation-evidence))
                 (ormap visit (slot-read-dependencies read)))))))
  (if (ormap visit roots) #t #f))

(def module-authoring-stage-test
  (test-suite "Default authoring construction and Interface admission"
    (poo-flow-test-case "computed defaults keep fresh receivers without constructor evidence dependencies"
      (def left (.o (:: @ poo-flow-module-style-policy-prototype)))
      (def right (.o (:: @ poo-flow-module-style-policy-prototype)))
      (defvalues (profile reads)
        (%call-with-recorded-slot-reads (lambda () (.get left authoring))))
      (def authoring-reads (filter (lambda (read) (eq? (slot-read-key read) 'authoring)) reads))
      (check-equal? (pair? authoring-reads) #t)
      (check-equal? (constructor-receipt? authoring-reads) #f)
      (check-equal? (eq? profile (.get left authoring)) #t)
      (check-equal? (eq? profile (.get right authoring)) #f)
      (check-equal? (eq? (.get profile executor) (.get right authoring executor)) #f)
      (check-equal? (eq? (.get profile types) (.get right authoring types)) #t)
      (.put! profile 'types #f)
      (check-exception
        (poo-flow-module-interface "invalid" (.o) '() authoring: profile) error?)
      ;; Mutating one default does not mutate another receiver's default.
      (check-equal? (object? (.get right authoring types)) #t)
      (check-equal? (object? (poo-flow-module-interface "valid" (.o) '()
                             authoring: (.get right authoring))) #t))
    (poo-flow-test-case "Interface validates once and the public factory still validates immediately"
      (def validations 0)
      (call-with-slot-read-observer
        (lambda (read)
          (when (and (eq? (slot-read-receiver read) ModuleAuthoringProfileContract)
                     (eq? (slot-read-key read) '.validate))
            (set! validations (+ validations 1))))
        (lambda ()
          (def policy (.o (:: @ poo-flow-module-style-policy-prototype)))
          (def raw (.get policy authoring))
          (check-equal? validations 0)
          (def interface (poo-flow-module-interface "checked" (.o) '() authoring: raw))
          (check-equal? validations 1)
          (check-equal? (eq? (.get interface authoring) raw) #t)
          ;; The public factory still validates immediately, independently of
          ;; the internal source-policy construction stage.
          (def public (poo-flow-default-module-authoring-profile))
          (check-equal? validations 2)
          (check-equal? (object? public) #t))))
    (poo-flow-test-case "actual authoring Contract changes invalidate completed Graph evidence"
      (def previous (.get ModuleAuthoringProfileContract value-contract))
      (dynamic-wind void
        (lambda ()
          (with-other-source
            (lambda (root _first _other)
              (write-file (path-expand "init.ss" root)
                "(poo-flow! mode: explicit :custom (example))"))
            (lambda (_root _first _other view)
              (def graph (.get view selected-graph))
              (check-equal? (.get graph status) 'ready)
              (.call graph admit-current)
              ;; Same value, new native revision. No forged evidence or custom
              ;; currentness closure substitutes for the real producer reads.
              (.put! ModuleAuthoringProfileContract 'value-contract previous)
              (check-exception (.call graph admit-current) stale-native-dependency?)
              (check-exception (.call view sources-current) stale-native-dependency?))))
        (lambda () (.put! ModuleAuthoringProfileContract 'value-contract previous))))))
