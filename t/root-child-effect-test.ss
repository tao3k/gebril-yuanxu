;;; Real selected service publication, with one test-only package callback effect.
(import :std/test :clan/poo/object
        (prefix-in :clan/poo/declarative-metadata metadata.)
        (only-in :std/error Error? Error-message)
        (only-in :yuanxu/observability/testing-case yuanxu-test-case)
        (only-in :yuanxu/observability/testing-fixture with-yuanxu-fixture)
        (only-in :yuanxu/t/qualification/service-publication/fixtures ServicesFixture write-source))
(export root-child-effect-test test-cleanup!)
(def completed 0)
(def (cause failure)
  (if (metadata.failure? failure) (cause (metadata.failure-cause failure)) failure))
(def (test-cleanup!)
  (unless (= completed 1) (error "incomplete real package effect control"))
  (displayln "REAL-PACKAGE-EFFECT: 1 case completed"))
(def root-child-effect-test
  (test-suite "Current real service publication post-effect source check"
    (yuanxu-test-case "silent source change after accepted admission cannot publish"
      (with-yuanxu-fixture (fixture ServicesFixture)
        (def publication (.get fixture publication))
        (def Parent (.get publication value))
        (def cached (.get Parent plan))
        (.def (Release @ Parent)
          config: =>.+ (.o postgresql: =>.+ (.o settings: =>.+ (.o port: 5433))))
        (def checks 0)
        (def target (path-expand "modules/services/postgresql/postgresql.json" (.get fixture root)))
        (def Effectful
          (.cc publication
            package-current:
            (lambda ()
              (set! checks (+ checks 1))
              ;; First call is before admission; the second is after ACCEPTED
              ;; evidence. The callback returns normally: no injected exception.
              (when (= checks 2) (write-source target "{}")))))
        (defvalues (receipt next failure) (.call Effectful .publish Parent Release))
        (check-equal? checks 2)
        (check-equal? receipt #f)
        (check-equal? (eq? next Parent) #t)
        (check-equal? (metadata.failure? failure) #t)
        (check-equal? (Error? (cause failure)) #t)
        (check-equal? (Error-message (cause failure)) "selected configuration asset changed")
        (check-equal? (.get cached postgresql port) 5432)
        (write (list 'POST-PACKAGE-REJECT checks (Error-message (cause failure))))
        (newline)
        (set! completed (+ completed 1))))))
