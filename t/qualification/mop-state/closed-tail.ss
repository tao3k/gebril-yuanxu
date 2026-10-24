;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Minimal probe only; real service validation is separate in each test suite.
(import :std/test :clan/poo/object
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/object-types/contracts yuanxu-classification-evidence)
        (only-in :yuanxu/admission/source SourceAdmissionContract.)
        (only-in :yuanxu/module-system/source/admission current-module-source-phase))
(export probe on-file refuses)
(def (refuses result message)
  (check-equal? (Error? result) #t)
  (check-equal? (Error-message result) message))
(def (probe paths)
  (.def Subject port: 5432 unused: (error "unselected branch forced"))
  (.def Dependency port: 5432)
  (.def (Descriptor @ SourceAdmissionContract.)
    identity: 'test/closed-tail
    marker: 0
    source-inputs: (map (lambda (path) (cons path "{}")) paths)
    .classify: (lambda (candidate context)
                 (yuanxu-classification-evidence identity candidate #t '() context))
    .obligations:
    (lambda (candidate _context)
      (if (equal? (list (.get Descriptor marker) (.get candidate port) (.get Dependency port))
                  '(0 5432 5432)) '() (list (.o kind: 'probe-policy)))))
  (.o contract: Descriptor candidate: Subject external: Dependency))
(def (on-file path effect)
  (lambda (key _amount)
    (when (and (eq? (current-module-source-phase) 'return-currentness)
               (pair? key) (eq? (car key) 'file-read) (equal? (caddr key) path))
      (effect))))
