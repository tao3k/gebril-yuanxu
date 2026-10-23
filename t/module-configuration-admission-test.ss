;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Generic declared configuration admission uses the existing POO Types.
(import :std/test :clan/poo/object
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :clan/poo/type String)
        (only-in :clan/poo/mop Function)
        (only-in :yuanxu/object-types/contracts YuanxuContract.)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/source/admission admit-module-configuration!))
(export module-configuration-admission-test)

;; A declaration associates values and Types without another option registry.
(def declaration
  (.o admissions: (.o Config: (.o export-path: '(config) contract-path: '(types config)))))
(.def (Settings @ ObjectContract.) responsibilities: (.o message: String))

(def module-configuration-admission-test
  (test-suite "Declared module configuration"
    (yuanxu-test-case "POO Type and contextual Contract retain the final receiver"
      (.def Parent message: "parent")
      (check-equal? (.get Parent message) "parent")
      (.def (Child @ Parent) message: "child")
      (def scope (.o config: Child types: (.o config: Settings)))
      (check-equal? (.get (admit-module-configuration! scope declaration 'fixture #f) config message) "child")
      (def contract (.cc YuanxuContract. 'identity 'fixture/config 'value-contract Settings))
      (check-equal? (.get (admit-module-configuration!
                           (.cc scope 'types (.o config: contract)) declaration 'fixture #f)
                         config message) "child")
      (check-equal? (.get Parent message) "parent"))
    (yuanxu-test-case "missing declarations and malformed or missing Types refuse"
      (def scope (.o config: (.o message: "ok") types: (.o config: Settings)))
      (check-exception (admit-module-configuration! (.o) declaration 'fixture #f) error?)
      (check-exception (admit-module-configuration! #f declaration 'fixture #f) error?)
      (check-exception (admit-module-configuration! scope (.o) 'fixture #f) error?)
      (check-exception (admit-module-configuration!
                        (.cc scope 'types (.o)) declaration 'fixture #f) error?)
      (check-exception (admit-module-configuration!
                        (.cc scope 'types (.o config: #f)) declaration 'fixture #f) error?))
    (yuanxu-test-case "closed names and final value Types survive extension"
      (def scope (.o config: (.o message: "ok") types: (.o config: Settings)))
      (check-exception (admit-module-configuration!
                        (.cc scope 'config (.o message: 123)) declaration 'fixture #f) error?)
      (def touched? #f)
      (def unknown (.o message: "ok" typo: (begin (set! touched? #t) 1)))
      (check-exception (admit-module-configuration!
                        (.cc scope 'config unknown) declaration 'fixture #f) error?)
      (check-equal? touched? #f))
    (yuanxu-test-case "recursive Function wrapping remains on the linked configuration"
      (def calls 0)
      (def descriptor
        (.cc ObjectContract. 'responsibilities
          (.o callback: (Function (list String) (list String)))))
      (for-each
        (lambda (type)
          (def scope
            (.o config: (.o callback: (lambda (_text) (set! calls (+ calls 1)) 123))
                types: (.o config: type)))
          (def checked (.get (admit-module-configuration! scope declaration 'fixture #f) config))
          (def before calls)
          (check-exception ((.get checked callback) 123) error?)
          (check-equal? calls before)
          (check-exception ((.get checked callback) "valid input") error?)
          (check-equal? calls (+ before 1)))
        (list descriptor (.cc YuanxuContract. 'identity 'fixture/callback 'value-contract descriptor))))
    (yuanxu-test-case "declaration paths can name an existing domain Contract"
      (def settings-type Settings)
      (def declared
        (.o admissions: (.o Settings: (.o export-path: '(config) contract-path: '(types Settings)))))
      (def scope (.o config: (.o message: "selected") types: (.o Settings: settings-type)))
      (check-equal? (.get (admit-module-configuration! scope declared 'fixture #f) config message)
                    "selected"))))
