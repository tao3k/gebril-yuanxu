;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :clan/poo/object
        (only-in :clan/poo/mop element? validate Bool)
        (only-in :clan/poo/type String)
        :clan/poo/object-contract
        :yuanxu/modules/json-schema/contracts)
(export json-schema-value-contract-test)

(def PortObject
  (schema-value-contract 'test/port
    '((type . "object") (properties . ((port . ((type . "integer") (minimum . 1) (maximum . 65535)))))
      (required . ("port")) (additionalProperties . #f))))

(def json-schema-value-contract-test
  (test-suite "JsonSchema value contracts without Core admission"
    (test-case "typed scalar enum intersects the base type and stays diagnostic"
      (def contract (schema-value-contract 'test/instance
                      '((type . "string") (enum . ("t3.medium")))))
      (check-equal? (element? contract "t3.medium") #t)
      (check-equal? (element? contract "t3.small") #f)
      (check-equal? (element? contract 7) #f)
      (check-equal? (pair? (diagnose contract "t3.small" '(web settings instance_type))) #t)
      (check-equal? (.get (car (diagnose contract "t3.small" '(web settings instance_type))) path)
                    '(web settings instance_type))
      (check-exception (schema-value-contract 'test/empty-enum '((enum . ()))) error?)
      (check-exception (schema-value-contract 'test/composite-enum
                         '((enum . (((name . "web")))))) error?))
    (test-case "Schema Type participates in public responsibilities"
      (def contract (.cc ObjectContract. responsibilities: (.o name: String endpoint: PortObject)))
      (def value (.o name: "api" endpoint: (.o port: 443)))
      (check-equal? (element? contract value) #t)
      (check-equal? (diagnose contract value) '())
      ;; ObjectContract returns its final validated receiver; unchanged data
      ;; does not promise that receiver is eq? to the original lazy object.
      (def checked (validate contract value))
      (check-equal? (diagnose contract checked) '())
      (check-equal? (.get checked name) "api")
      (check-equal? (.get checked endpoint port) 443)
      (check-equal? (eq? (.get contract prepared-responsibilities endpoint) PortObject) #t))
    (test-case "Schema diagnostics retain the precise prefixed path"
      (def failures (diagnose PortObject (.o port: 443 prot: 80) '(service)))
      (check-equal? (element? PortObject (.o port: 443 prot: 80)) #f)
      (check-equal? (.get (car failures) kind) 'schema-rejected)
      (check-equal? (.get (car failures) path) '(service prot))
      (check-equal? (.get (car (diagnose PortObject (.o) '(service))) path) '(service port)))
    (test-case "primitive constraints and false schemas agree between boolean and diagnostic paths"
      (def bounded (schema-value-contract 'test/bounded
                    '((type . "string") (minLength . 2) (pattern . "^a"))))
      (check-equal? (element? bounded "abc") #t)
      (check-equal? (diagnose bounded "abc") '())
      (check-equal? (element? bounded "b") #f)
      (check-equal? (pair? (diagnose bounded "b")) #t)
      (check-equal? (element? (schema-value-contract 'test/false #f) 42) #f)
      (check-equal? (pair? (diagnose (schema-value-contract 'test/false #f) 42)) #t)
      (check-equal? (diagnose (schema-value-contract 'test/true #t) 42) '()))
    (test-case "records in arrays and unions retain existing node semantics"
      (def array-contract
        (schema-value-contract 'test/array
          '((type . "array") (minItems . 1) (items . ((type . "object")
            (properties . ((name . ((type . "string")))))
            (required . ("name")) (additionalProperties . #f))))))
      (check-equal? (element? array-contract (list (.o name: "web"))) #t)
      (check-equal? (element? array-contract (list (.o name: 7))) #f)
      (check-equal? (.get (car (diagnose array-contract (list (.o name: 7)))) path) '(0 name))
      (def union-contract (schema-value-contract 'test/union
                            '((anyOf . (((type . "null")) ((type . "integer")))))))
      (check-equal? (element? union-contract 'null) #t)
      (check-equal? (element? union-contract 7) #t)
      (check-equal? (element? union-contract "7") #f)
      (check-equal? (pair? (diagnose union-contract "7")) #t))
    (test-case "projection preserves the original candidate and adapts plain Types"
      (def contract (.cc ProjectionContract. constraint: String
                        project: (lambda (value) (.get value data))))
      (def value (.o data: "text"))
      (check-equal? (diagnose contract value) '())
      (check-equal? (eq? (validate contract value) value) #t)
      (def parent-prepared (.get contract prepared-constraint))
      (def child (.cc contract constraint: Bool))
      (check-equal? (element? child (.o data: #t)) #t)
      (check-equal? (element? child value) #f)
      (check-equal? (eq? parent-prepared (.get child prepared-constraint)) #f))
    (test-case "unsupported Schema and invalid projection remain explicit failures"
      (check-exception (schema-value-contract 'test/unsupported
                         '((type . "string") (unsupportedKeyword . #t))) error?)
      (check-exception (diagnose (.cc ProjectionContract. constraint: PortObject project: 7) (.o)) error?))
    (test-case "Schema factories and projection use final inherited values after parent cache"
      (.def (parent @ [] config)
        config: (.o port: 80)
        resource: (.o target-port: (.get config port)))
      (def cached (.get parent resource target-port))
      (def contract (.cc ProjectionContract. constraint: PortObject project: (lambda (value) (.get value config))))
      (check-equal? (diagnose contract parent) '())
      (.def (child @ parent) config: =>.+ (.o port: 443))
      (check-equal? (.get child resource target-port) 443)
      (check-equal? cached 80)
      (check-equal? (diagnose contract child) '()))))
