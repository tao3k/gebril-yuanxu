(import :yuanxu/object-syntax/path-slots
        :yuanxu/profile-composition/selection-syntax
        (only-in :yuanxu/scenarios/funflow/scope Funflow)
        (only-in :clan/poo/object .get .+ .slot?))
(.def ProjectCI funflow: (use-module Funflow as ff (.o (:: @ ff))))
(def (with-release-manifest inherited-artifacts)
  (append inherited-artifacts '(release-manifest)))
(.def (ManifestCI @ ProjectCI)
  funflow.profiles.gerbil-scheme.build: =>.+
  {artifact-outputs: => with-release-manifest})
(.def SmokeProject
  funflow:
  (use-module Funflow as ff
    (.+ ff
      {profiles.gerbil-scheme: =>.+
       {smoke:
        (.o (:: @ (.get ff prototypes check))
          check-name: 'smoke
          command-vector: '("gerbil" "env" "./smoke-tests.ss"))}})))
(.def (TypoCI @ ProjectCI)
  funflow.profiles.gerbil-scheme.build: =>.+
  {commmand-vector: '("wrong")})
(unless
  (and
    (equal? (.get ManifestCI funflow profiles gerbil-scheme build artifact-outputs)
            '(build-log release-manifest))
    (.slot? (.get SmokeProject funflow profiles gerbil-scheme) 'smoke)
    (equal? (map (lambda (check) (.get check check-name))
                 (.get SmokeProject funflow profiles gerbil-scheme pipeline checks))
            '(build test package))
    (.slot? (.get TypoCI funflow profiles gerbil-scheme build) 'commmand-vector)
    (equal? (.get TypoCI funflow profiles gerbil-scheme build command-vector)
            '("gerbil" "build")))
  (error "configuration interface reflection probe failed"))
(displayln "PASS: inherited transformation, unselected new Check and unused typo slot")
