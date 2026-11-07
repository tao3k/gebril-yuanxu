let Check = { command : List Text, artifacts : List Text }
let base : Check =
      { command = [ "gerbil", "build" ], artifacts = [ "build-log" ] }
let makeProfile = \(check : Check) -> { build = check, checks = [ check ] }
let childCheck = base // { artifacts = [ "release-log" ] }
in { parent = (makeProfile base).checks
   , child = (makeProfile childCheck).checks
   }
