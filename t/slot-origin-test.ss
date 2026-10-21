;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test :yuanxu/object-syntax/path-slots
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :clan/poo/object .get .+ .cc .all-slots .put! object-slots with-slots)
        (prefix-in (only-in :clan/poo/object make-object) poo-)
        (only-in :clan/poo/mop Slot)
        (only-in :yuanxu/configuration/slot-origin field-slot-origins/value admit-field-sources!)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer)
        (only-in :yuanxu/configuration/json config-json-file config-field-origin)
        (only-in :yuanxu/observability/testing-fixture yuanxu-test-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures DirectoryFixture))
(export slot-origin-test)
(def slot-origin-test
  (test-suite "Native slot-attached Scheme provenance"
    (yuanxu-test-case "assignment, native transform, inheritance and right-hand copy keep their own origins"
      (.def Base port: 5432)
      (.def (First @ Base) (port => + 1))
      (.def (Second @ First) port: 5440)
      (def origins (field-slot-origins/value Second '(port)))
      (def reads 0)
      (def stats 0)
      (parameterize ((current-module-source-observer
                      (lambda (key amount)
                        (case key
                          ((reads) (set! reads (+ reads amount)))
                          ((stats) (set! stats (+ stats amount)))))))
        ;; Three inherited specifications from this same source still enroll
        ;; all their requirements, while sharing one physical observation.
        (admit-field-sources! Second '((port))))
      (check-equal? reads 1)
      (check-equal? stats 1)
      (check-equal? (.get Second port) 5440)
      (check-equal? (map (lambda (origin) (.get origin operation)) origins) '(assign => assign))
      (check-equal? (map (lambda (origin) (.get origin kind)) origins) '(scheme-slot scheme-slot scheme-slot))
      (def overlay (.o port: 5500))
      (def combined (.+ Second overlay))
      (check-equal? (eq? (cdr (assq 'port (object-slots combined)))
                         (cdr (assq 'port (object-slots overlay)))) #t)
      (check-equal? (.get combined port) 5500)
      (check-equal? (.get (car (field-slot-origins/value combined '(port))) line)
                    (.get (car (field-slot-origins/value overlay '(port))) line))
      (check-equal? (.all-slots combined) '(port))
      (def paired (.o (port ? 0) port: 5440))
      (check-equal? (.get paired port) 5440)
      (check-equal? (.get (car (field-slot-origins/value paired '(port))) operation) 'assign)
      ;; An uninstrumented explicit .cc write cannot borrow an inherited locator.
      (check-equal? (field-slot-origins/value (.cc Second port: 5600) '(port)) '()))
    (yuanxu-test-case "shared prefixes, payload hygiene and undemanded fields remain native"
      (def left-count 0)
      (def unused-count 0)
      (.def Base service: (.o left: (.o port: 5432) right: (.o port: 5432)))
      (.def (Child @ Base)
        service.left: =>.+
        {port: (begin (set! left-count (+ left-count 1)) 5433)}
        service.right: =>.+
        {port: (begin (set! unused-count (+ unused-count 1)) 5440)})
      (admit-field-sources! Child '((service left port)))
      (check-equal? (list left-count unused-count) '(0 0))
      (check-equal? (.get Child service left port) 5433)
      (check-equal? (.get Child service left port) 5433)
      (check-equal? (list left-count unused-count) '(1 0))
      (check-equal? (.get (car (field-slot-origins/value Child '(service left port))) operation) 'assign))
    (yuanxu-test-case "native cc retains untouched specifications and never borrows an overwritten field source"
      (.def Parent port: 5432 label: 'database)
      (def cached (.get Parent port))
      (def parent-origin (car (field-slot-origins/value Parent '(port))))
      (def copy (.cc Parent label: 'release))
      (check-equal? (eq? (cdr (assq 'port (object-slots copy)))
                         (cdr (assq 'port (object-slots Parent)))) #t)
      (check-equal? (.get copy port) 5432)
      (check-equal? (.get (car (field-slot-origins/value copy '(port))) line)
                    (.get parent-origin line))
      ;; Equal-value replacement is still a new unlocated write.
      (def replacement (.cc copy port: 5432))
      (check-equal? (eq? (cdr (assq 'port (object-slots replacement)))
                         (cdr (assq 'port (object-slots copy)))) #f)
      (check-equal? (field-slot-origins/value replacement '(port)) '())
      (.def Container database: replacement)
      (check-equal? (field-slot-origins/value Container '(database port)) '())
      (check-equal? (.get Parent port) cached))
    (yuanxu-test-case "native explicit instance assignments shadow declaration sources without becoming inherited caches"
      (.def Parent port: 5432)
      (check-equal? (.get Parent port) 5432)
      (.put! Parent 'port 5440)
      (check-equal? (.get Parent port) 5440)
      (check-equal? (field-slot-origins/value Parent '(port)) '())
      ;; Native .cc copies specifications, not the explicit instance assignment.
      (def copy (.cc Parent))
      (check-equal? (.get copy port) 5432)
      (check-equal? (length (field-slot-origins/value copy '(port))) 1))
    (yuanxu-test-case "native declaration compilation cannot inherit a replaced field's source"
      (.def Parent port: 5432)
      (check-equal? (.get Parent port) 5432)
      (def descriptor (.o (:: @ (.get Slot proto)) constant: 5440))
      (def child
        (poo-make-object supers: (list Parent)
          declarations: (list (cons 'port descriptor))))
      (check-equal? (.get child port) 5440)
      (check-equal? (field-slot-origins/value child '(port)) '())
      (check-equal? (.get Parent port) 5432))
    (yuanxu-test-fixture "JSON baseline remains attached to the effective Scheme field diagnostic"
      (fixture DirectoryFixture)
      (with-slots (root) fixture
        (def path (path-expand "postgresql.json" root))
        (call-with-output-file path (lambda (port) (display "{\"port\":5432}" port)))
        (def document (config-json-file path))
        (.def (Child @ (.get document value)) port: 5433)
        (def origin (config-field-origin document '(port) (.get Child port) Child))
        (check-equal? (.get origin kind) 'scheme-slot)
        (check-equal? (.get origin baseline source) (path-normalize path))
        (check-equal? (.get origin baseline kind) 'derived-value)
        (check-equal? (.get origin baseline presence) 'explicit)
        (.def (Same @ (.get document value)) port: 5432)
        (def same-origin (config-field-origin document '(port) (.get Same port) Same))
        (check-equal? (.get same-origin kind) 'scheme-slot)
        (check-equal? (.get same-origin baseline kind) 'json-field)))))
