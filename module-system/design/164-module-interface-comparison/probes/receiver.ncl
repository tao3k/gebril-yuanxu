let base = {
  build = {
    command | default = ["gerbil", "build"],
    artifacts | default = ["build-log"],
  },
  checks = [build],
} in
let child = base & { build.artifacts = ["release-log"] } in
{
  parent = base.checks,
  child = child.checks,
}
