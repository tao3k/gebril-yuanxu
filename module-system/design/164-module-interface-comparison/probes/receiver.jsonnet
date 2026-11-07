local base = {
  build: { command: ['gerbil', 'build'], artifacts: ['build-log'] },
  checks: [self.build],
};
local child = base + { build+: { artifacts: ['release-log'] } };
local saved = base.checks;
local frozen = child + { checks: saved };
{
  parent: base.checks[0].artifacts,
  inheritedChild: child.checks[0].artifacts,
  frozenChild: frozen.checks[0].artifacts,
}
