let
  base = rec {
    build = { command = [ "gerbil" "build" ]; artifacts = [ "build-log" ]; };
    checks = [ build ];
  };
  child = base // {
    build = base.build // { artifacts = [ "release-log" ]; };
  };
  makeProfile = check: { build = check; checks = [ check ]; };
  fresh = makeProfile child.build;
in {
  parent = (builtins.head base.checks).artifacts;
  shallowChild = (builtins.head child.checks).artifacts;
  reconstructedChild = (builtins.head fresh.checks).artifacts;
}
