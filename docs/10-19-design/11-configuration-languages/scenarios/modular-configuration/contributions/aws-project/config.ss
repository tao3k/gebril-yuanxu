;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; DESIGN SOURCE ONLY. User input, not a deployment service or command wrapper.
;;; Minimal existing-network case. Replace account-specific identifiers and AMI.
(def Config
  (.o provider: (.o aws: (list (.o region: "eu-central-1" profile: "team")))
      resource:
      (.o aws_security_group:
          (.o web: (.o name: "team-web"
                       vpc_id: "vpc-REPLACE_ME"
                       ingress: (list (.o protocol: "tcp" from_port: 443 to_port: 443
                                          cidr_blocks: '("192.0.2.0/24")))))
          aws_instance:
          (.o web: (.o ami: "ami-REPLACE_ME"
                       instance_type: "t3.small"
                       subnet_id: "subnet-REPLACE_ME"
                       key_name: "team"
                       vpc_security_group_ids: '("${aws_security_group.web.id}")
                       tags: (.o Name: "team-web" Environment: "production"))))
      data: (.o)))
;;; Existing VPC/subnet/key are explicit dependencies of this case. The richer
;;; scenarios/aws/scenarios/profiles/config.ss Recipe creates its own network/key.
