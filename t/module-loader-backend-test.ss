;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

(import (only-in :std/test test-suite check-equal? check-exception)
        (only-in :clan/poo/object .o .get .cc)
        (only-in :clan/poo/mop make-instance validate TypeError?)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        :yuanxu/module-system/source/objects
        :yuanxu/module-system/loader/objects)

(export module-loader-backend-test)

(def module-loader-backend-test
  (test-suite "Core Module Loader Backend"
    (yuanxu-test-case "lazy values do not invoke their backend before force"
      (let* ((calls 0)
             (source (make-yuanxu-module-local-source "feature/interface.ss"))
             (module (.o name: 'feature))
             (load (lambda (requested)
                     (set! calls (+ calls 1))
                     (if (yuanxu-module-source-ref=? requested source) module #f)))
             (backend
              (make-instance ModuleLoaderBackend name: 'static source-kind: 'local load: load))
             (checked-load (.get backend load))
             (deferred (yuanxu-make-lazy-load-plan (list backend) source))
             (cached (.get deferred receipt)))
        (check-equal? calls 0)
        (check-equal? (.get deferred forced?) #f)
        (check-equal? (.get deferred receipt code)
                      'deferred)
        (let* ((forced (yuanxu-force-lazy-load-plan (.cc deferred tenant: 'release)))
               (receipt (.get forced receipt)))
          (check-equal? calls 1)
          (check-equal? (.get forced forced?) #t)
          (check-equal? (.get receipt loaded?) #t)
          (check-equal? (yuanxu-module-load-receipt->alist receipt)
                        '((source (kind . local)
                                  (value . "feature/interface.ss")
                                  (metadata))
                          (module . feature)
                          (backend-name . static)
                          (loaded? . #t)
                          (code . loaded)
                          (messages)
                          (metadata)))
          (check-equal? (.get forced tenant) 'release)
          (check-equal? (.get deferred forced?) #f)
          (check-equal? (eq? (.get deferred receipt) cached) #t)
          (check-equal? (eq? (.get (car (.get forced backends)) load) checked-load) #t)
          (yuanxu-force-lazy-load-plan forced)
          (check-equal? calls 2))))
    (yuanxu-test-case "unsupported sources remain missing receipts"
      (let* ((source (make-yuanxu-module-package-source 'other))
             (backend (yuanxu-module-static-loader 'local 'local '()))
             (receipt (yuanxu-module-load-source-receipt
                       (list backend) source)))
        (check-equal? (.get receipt loaded?) #f)
        (check-equal? (.get receipt code)
                      'missing-loader)))
    (yuanxu-test-case "static loading reuses source bindings and leaves later entries unobserved"
      (def source (make-yuanxu-module-local-source "feature/interface.ss"))
      (def module (.o name: 'feature deferred: (error "business slot forced")))
      (def binding (make-instance ModuleSourceBinding source: source module: module))
      (def backend
        (yuanxu-module-static-loader 'static 'local
          (list binding (.o source: (error "later binding forced")
                            module: (error "later module forced")))))
      (def receipt (yuanxu-module-load-source-receipt (list backend) source))
      (check-equal? (eq? (.get receipt module) module) #t)
      (check-equal? (.get receipt code) 'loaded))
    (yuanxu-test-case "native Function normalization is not an identity-preserving inspection"
      (def calls 0)
      (def source (make-yuanxu-module-local-source "feature/interface.ss"))
      (def module (.o name: 'feature))
      (def load (lambda (_) (set! calls (+ calls 1)) module))
      (def backend (make-instance ModuleLoaderBackend name: 'probe source-kind: 'local load: load))
      (check-equal? (eq? (.get backend load) load) #f)
      (check-equal? (eq? (.get backend load) (.get backend load)) #t)
      (def rechecked (validate ModuleLoaderBackend backend))
      (check-equal? calls 0)
      (check-equal? (eq? (.get rechecked load) (.get backend load)) #f)
      (check-equal? (eq? ((.get rechecked load) source) module) #t)
      (check-equal? calls 1)
      (check-exception ((.get rechecked load) #f) TypeError?)
      (check-equal? calls 1))
    (yuanxu-test-case "receipt data uses native field validation"
      (def source (make-yuanxu-module-local-source "feature/interface.ss"))
      (check-exception
        (make-instance ModuleLoadReceipt source: source code: 'loaded messages: '(7))
        TypeError?)
      (check-exception
        (make-instance ModuleLoadReceipt source: source code: 'loaded backend-name: 17)
        TypeError?)
      (check-exception
        (make-instance ModuleLoadReceipt source: source code: 'deferred
          metadata: '(("owner" . test))) TypeError?)
      (def calls 0)
      (check-exception
        (make-instance ModuleLoadReceipt source: source code: 'deferred
          metadata: (list (cons 'owner (lambda () (set! calls (+ calls 1))))))
        TypeError?)
      (check-equal? calls 0)
      (def accepted
        (make-instance ModuleLoadReceipt source: source code: 'deferred
          metadata: '((owner . test) (label . "fixture") (enabled? . #f) (backend-count . 2))))
      (check-equal? (.get accepted metadata)
        '((owner . test) (label . "fixture") (enabled? . #f) (backend-count . 2)))
      (check-exception
        (make-instance ModuleLoaderBackend name: "untyped-id" source-kind: 'local load: identity)
        TypeError?))))
