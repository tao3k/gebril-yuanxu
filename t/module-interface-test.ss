;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .ref .cc .get .mix)
        (only-in :clan/poo/type Record String)
        (only-in :clan/poo/mop validate)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/config)

(export module-interface-test)

(def module-interface-test
  (test-suite "Core Module Interface mechanism"
    (yuanxu-test-case "schema indexing and option policy are product-neutral"
      (let* ((schema (Record endpoint: [String] layers: [String policy: 'append]))
             (index (yuanxu-module-interface-schema-index schema))
             (append-policy (hash-get index "layers")))
        (check-equal? (.ref (hash-get index "endpoint") 'type) String)
        (check-equal? (.ref append-policy 'policy) 'append)
        (check-equal? (yuanxu-module-kind=? "core.module" "core.module") #t)))
    (yuanxu-test-case "native Record preserves defaults, constants and optional absence"
      (def shape (Record name: [String] mode: [String default: "dev"]
                         backend: [String constant: "postgresql"]
                         note: [String optional: #t]))
      (def value (validate shape (.mix (.o name: "api") (.get shape proto))))
      (check-equal? (.get value mode) "dev")
      (check-equal? (.get value backend) "postgresql")
      (check-exception (validate shape (.o name: 42 mode: "dev" backend: "postgresql"))
                       (lambda (_) #t))
      (check-exception (validate shape (.o name: "api" mode: "dev" backend: "mysql"))
                       (lambda (_) #t)))
    (yuanxu-test-case "derived Record index follows its own final declaration after parent cache"
      (def shape (Record port: [String default: "5432"]))
      (def parent (.o schemas: shape
                     (index (yuanxu-module-interface-schema-index schemas))))
      (check-equal? (.get (hash-get (.get parent index) "port") default) "5432")
      (def child (.cc parent schemas: (Record [shape] port: [String default: "5440"])))
      (check-equal? (.get (hash-get (.get child index) "port") default) "5440")
      (check-equal? (.get (hash-get (.get parent index) "port") default) "5432"))
    (yuanxu-test-case "object inspection keeps declared slot values"
      (check-equal? (yuanxu-module-object->alist (.o identity: 'core))
                    '((identity . core))))))
