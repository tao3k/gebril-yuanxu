;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :std/test
        (only-in :gerbil/expander core-resolve-library-module-path)
        (only-in :std/io/tempfile call-with-temporary-directory)
        (only-in :clan/poo/object .get)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/module-system/source/admission current-module-source-observer
                 module-source-read module-source-admit-current!)
        (only-in :yuanxu/module-system/building/configuration-source yuanxu-configuration-source))
(export module-configuration-source-test)
(def (write-source path text)
  (call-with-output-file (list path: path truncate: #t) (cut display text <>)))
(def module-configuration-source-test
  (test-suite "Observed native configuration roles"
    (yuanxu-test-case "reader return owns the final check, not a duplicate after private cleanup"
      (call-with-temporary-directory "configuration-return-guard"
        (lambda (root)
          (def config (path-expand "config.ss" root))
          (def dependency (path-expand "context-input.ss" root))
          (write-source (path-expand "gerbil.pkg" root) "(package: configuration-return-control)")
          (write-source config "(def Config 'ready) (export Config)")
          (write-source dependency "context-version-one")
          (def inputs (list (cons dependency (module-source-read dependency))))
          (def reads 0)
          (def (context!) (module-source-admit-current! inputs))
          (def result
            (parameterize ((current-module-source-observer
                            (lambda (key amount)
                              (when (and (pair? key) (eq? (car key) 'file-read)
                                         (equal? (caddr key) dependency))
                                (set! reads (+ reads amount))))))
              (yuanxu-configuration-source config 'Config context! role-sources: (list config))))
          ;; One preparation/pre-bootstrap window, reader pre-import and post-import.
          ;; Count actual opens, not requests served by a pure-window byte hit.
          (check-equal? reads 3)
          (check-equal? (.get result value) 'ready)
          (write-source dependency "context-version-two")
          (check-exception ((.get result admit-current)) error?))))
    (yuanxu-test-case "pure import checks do not reuse observations across initialization effects"
      (call-with-temporary-directory "configuration-initialization-effect"
        (lambda (root)
          (def config (path-expand "config.ss" root))
          (def objects (path-expand "objects.ss" root))
          (write-source (path-expand "gerbil.pkg" root) "(package: configuration-effect-control)")
          (write-source config "(import \"objects.ss\") (def Config Profile) (export Config)")
          (write-source objects
            (call-with-output-string
              (lambda (port)
                (write `(def Profile
                          (begin
                            (call-with-output-file (list path: ,config truncate: #t)
                              (lambda (port) (display "(def Config 'changed)" port)))
                            'initialized)) port)
                (write '(export Profile) port))))
          (def entry-reads 0)
          (parameterize ((current-module-source-observer
                          (lambda (kind amount)
                            (when (equal? kind (list 'file-read 'configuration-current config))
                              (set! entry-reads (+ entry-reads amount))))))
            (check-exception
              (yuanxu-configuration-source config 'Config void role-sources: (list config objects)) error?))
          ;; Exactly the pre/post complete guards read the private entry; SDK
          ;; imports check their own dependency subgraphs, not this role again.
          (check-equal? entry-reads 2))))
    (yuanxu-test-case "canonical public source imports work; foreign same-identity source never runs"
      (call-with-temporary-directory "configuration-public-dependency"
        (lambda (root)
          (def config (path-expand "config.ss" root))
          (def dependency (core-resolve-library-module-path ':clan/poo/declarative-metadata))
          (write-source (path-expand "gerbil.pkg" root) "(package: configuration-public-control)")
          (write-source config
            (call-with-output-string
              (lambda (port)
                (write `(import (only-in ,dependency atom formula?)) port)
                (write '(def Config (formula? (atom 'ready))) port))))
          (check-equal?
            (.get (yuanxu-configuration-source config 'Config void role-sources: (list config)) value) #t)
          (def foreign (path-expand "declarative-metadata.ss" root))
          (def marker (path-expand "executed" root))
          (write-source foreign
            (string-append "package: clan/poo\n(call-with-output-file "
              (call-with-output-string (cut write marker <>))
              " (lambda (p) (display \"forbidden\" p)))\n"))
          (write-source config
            (call-with-output-string
              (lambda (port) (write `(import ,foreign) port) (write '(def Config #t) port))))
          (check-exception
            (yuanxu-configuration-source config 'Config void role-sources: (list config)) error?)
          (check-equal? (file-exists? marker) #f))))
    (yuanxu-test-case "fresh private role imports, source currentness and cache isolation"
      (call-with-temporary-directory "configuration-role-control"
        (lambda (root)
          (let ((config (path-expand "config.ss" root))
                (objects (path-expand "objects.ss" root)))
            (write-source (path-expand "gerbil.pkg" root) "(package: configuration-control)")
            (write-source objects "(import :clan/poo/object) (def Profile (.o answer: 1)) (export Profile)")
            (write-source config "(import \"objects.ss\") (def Config Profile) (export Config)")
            (def context-checks 0)
            (def (context!) (set! context-checks (1+ context-checks)))
            (let (parent (yuanxu-configuration-source config 'Config context! role-sources: (list config objects)))
              (check-equal? (.get parent value answer) 1)
              (set! context-checks 0)
              ((.get parent admit-current))
              (check-equal? context-checks 1)
              ((.get parent admit-current))
              (check-equal? context-checks 2)
              (write-source objects "(import :clan/poo/object) (def Profile (.o answer: 2)) (export Profile)")
              (check-exception ((.get parent admit-current)) error?)
              (let (child (yuanxu-configuration-source config 'Config void role-sources: (list config objects)))
                (check-equal? (.get child value answer) 2)
                (check-equal? (.get parent value answer) 1)
                ((.get child admit-current)))
              ;; A source not in the admitted role set may not hide behind the
              ;; native global import cache or bypass the source observations.
              (write-source config "(import \"unobserved.ss\") (def Config Hidden) (export Config)")
              (write-source (path-expand "unobserved.ss" root) "(def Hidden #t) (export Hidden)")
              (check-exception (yuanxu-configuration-source config 'Config void role-sources: (list config objects)) error?))))))))
