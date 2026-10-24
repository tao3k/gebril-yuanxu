;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :std/source this-source-file)
        (only-in :yuanxu/configuration/json config-json-file config-defaults))
(export Document)
(def Document
  (config-json-file (path-expand "postgresql.json" (path-directory (this-source-file)))))
(def Config
  (config-defaults (.o settings: (.o port: 5432) allowed-ports: '(5432))
                   (.get Document value)))
