;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Wire null recognition has no emitter/admission dependency.
(export yuanxu-json-schema-null?)

(def (yuanxu-json-schema-null? value)
  (or (eq? value 'null)
      (eq? value 'json-null)
      (void? value)))
