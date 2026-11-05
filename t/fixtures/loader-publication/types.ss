;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :yuanxu/module-system/loader/types ModuleLoaderBackend)
        (only-in :clan/poo/mop Type. define-type)
        (only-in :yuanxu/admission/source SourceAdmissionContract.))
(export BackendScopeContract BackendAdmission ModuleLoaderBackend)
(define-type (BackendScopeContract @ Type.)
  identity: 'fixture/backend-scope
  .element?: (o?/slots '(Backend types trace)))
(.def (BackendAdmission @ SourceAdmissionContract.)
  identity: 'fixture/backend
  value-contract: ModuleLoaderBackend)
