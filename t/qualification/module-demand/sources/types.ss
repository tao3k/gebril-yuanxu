;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :clan/poo/object
        (only-in :clan/poo/mop define-type Object)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :yuanxu/object-types/ports Port)
        (only-in :yuanxu/admission/source SourceAdmissionContract.))
(export ScopeContract)
(define-type (ScopeContract @ SourceAdmissionContract.)
  identity: 'module-demand/scope
  value-contract: (.cc ObjectContract. responsibilities: (.o config: Object port: Port))
  .obligations:
  (lambda (candidate context)
    (append
      (if (and (eq? (.get candidate config) (.get context effective-config))
               (= (.get candidate port) (.get context effective-config port)))
        '() (list (.o kind: 'final-config-mismatch)))
      (if (memv (.get candidate port) (.get context allowed-a))
        '() (list (.o kind: 'requirement-a)))
      (if (memv (.get candidate port) (.get context allowed-b))
        '() (list (.o kind: 'requirement-b))))))
