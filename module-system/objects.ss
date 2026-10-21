;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Core owns the semantic Module value; a product supplies its authoring Profile.
(import (only-in :clan/poo/object .o .mix .ref)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/module-system/schema/relations
                 SemanticImports.
                 yuanxu-empty-imports yuanxu-empty-capabilities
                 yuanxu-empty-profiles)
        :yuanxu/module-system/types)

(export SemanticModule. ModuleSourceRole. ModuleAuthoringProfile.
        make-semantic-module)

(def SemanticModule. (.ref SemanticModuleContract 'proto))
(def ModuleSourceRole. (.ref ModuleSourceRoleContract 'proto))
(def ModuleAuthoringProfile. (.ref ModuleAuthoringProfileContract 'proto))

(def (compose-semantic-module-imports inherited local)
  (if (eq? inherited SemanticImports.)
    local
    (.mix local inherited)))

(def (make-semantic-module identity-value authoring-value
                           imports: (imports-value (yuanxu-empty-imports))
                           capabilities: (capabilities-value (yuanxu-empty-capabilities))
                           profiles: (profiles-value (yuanxu-empty-profiles)))
  (validate SemanticModuleContract
    (.o (:: @ SemanticModule.)
        identity: identity-value
        (imports => compose-semantic-module-imports imports-value)
        capabilities: capabilities-value
        profiles: profiles-value
        authoring: authoring-value)))
