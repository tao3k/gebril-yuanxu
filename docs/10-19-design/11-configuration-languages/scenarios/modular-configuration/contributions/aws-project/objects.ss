;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; DESIGN SOURCE ONLY. Ordinary configuration is already an object.
(def Project Config)
;;; Inheritance is optional: retain the entire maintained configuration and
;;; existing resource names while changing the one machine's instance type.
(.def (LargerProject @ Project)
  resource: =>.+
  (.o aws_instance: =>.+
      (.o web: =>.+ (.o instance_type: "t3.medium"))))
