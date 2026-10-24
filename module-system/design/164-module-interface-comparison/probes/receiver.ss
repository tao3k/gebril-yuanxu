(import :yuanxu/object-syntax/path-slots
        (only-in :clan/poo/object .get))
(.def Base
  build: (.o command: '("gerbil" "build") artifacts: '(build-log))
  pipeline: (.o checks: (list build)))
(def parent-checks (.get Base pipeline checks))
(.def (Child @ Base) build: =>.+ {artifacts: '(release-log)})
(def child-checks (.get Child pipeline checks))
(.def (Frozen @ Child) pipeline: =>.+ {checks: parent-checks})
(unless (and
          (equal? (.get (car parent-checks) artifacts) '(build-log))
          (equal? (.get (car child-checks) artifacts) '(release-log))
          (eq? (car child-checks) (.get Child build))
          (eq? parent-checks (.get Base pipeline checks))
          (equal? (.get (car (.get Frozen pipeline checks)) artifacts) '(build-log)))
  (error "receiver probe failed"))
(displayln "PASS: effective child, retained parent cache and frozen-list control")
