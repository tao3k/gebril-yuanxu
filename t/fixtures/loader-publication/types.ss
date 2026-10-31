;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :yuanxu/module-system/loader/types ModuleLoaderBackend)
        (only-in :yuanxu/object-types/contracts yuanxu-predicate-contract)
        (only-in :yuanxu/admission/source SourceAdmissionContract.))
(export BackendScopeContract BackendAdmission ModuleLoaderBackend)
(def BackendScopeContract
  (yuanxu-predicate-contract 'fixture/backend-scope (o?/slots '(Backend types trace))))
(.def (BackendAdmission @ SourceAdmissionContract.)
  identity: 'fixture/backend
  value-contract: ModuleLoaderBackend)
