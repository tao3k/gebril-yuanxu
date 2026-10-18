;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; DESIGN SOURCE ONLY. This is an ordinary user contribution, not a required
;;; Deployment module interposed between the user and AWS.
(.def AWSProject
  identity: 'team/aws-project
  core:
  (.o requires: (.o AWS: (.o module-id: 'aws contract: AWSInterfaceContract))
      exports: (.o config: Config types: (.o Config: ConfigContract)
                   project: (.get AWS project)))
  features: (.o))
