;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Wire null recognition has no emitter/admission dependency.
(export poo-flow-json-schema-null?)

(def (poo-flow-json-schema-null? value)
  (or (eq? value 'null)
      (eq? value 'json-null)
      (void? value)))
