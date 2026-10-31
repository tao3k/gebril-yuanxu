# Research control: real NixOS service modules, no service activation.
{ nixpkgsPath, inputDirectory, scenario, guarded ? false }:
let
  pkgs = import (builtins.toPath nixpkgsPath) { system = "x86_64-linux"; };
  lib = pkgs.lib;
  text = builtins.readFile (inputDirectory + "/config.json");
  input = builtins.fromJSON text;
  saved = builtins.fromJSON (builtins.readFile (inputDirectory + "/saved.json"));
  expectedOwners = [ "gitea" "postgresql" ];
  result = import (builtins.toPath (nixpkgsPath + "/nixos")) {
    system = "x86_64-linux";
    configuration = { config, lib, ... }: {
      imports = [
        ({ ... }: { comparison.requirements = [ { owner = "postgresql"; ports = [ 5432 5433 ]; } ]; })
        (if scenario == "omitted" then {} else {
          comparison.requirements = [ {
            owner = "gitea";
            ports = if builtins.elem scenario [ "conflict" "priority" ] then [ 5440 ] else [ 5432 5433 ];
          } ];
        })
        (if scenario == "value-conflict" then { services.postgresql.settings.port = 5440; } else {})
        (if scenario == "priority" then { services.postgresql.settings.port = lib.mkForce 5433; } else {})
      ];
      options.comparison.requirements = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options.owner = lib.mkOption { type = lib.types.str; };
          options.ports = lib.mkOption { type = lib.types.listOf lib.types.port; };
        });
        default = [];
      };
      config = let
        port = config.services.postgresql.settings.port;
        clientPort = config.services.gitea.database.port;
        requirements = config.comparison.requirements;
        plan = if scenario == "stale-plan" then saved.plan else {
          postgresql.port = port;
          gitea.databasePort = clientPort;
        };
      in {
        system.stateVersion = "25.11";
        boot.loader.grub.enable = false;
        fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
        networking.hostName = "comparison";
        services.postgresql.settings.port = input.port;
        services.gitea = {
          enable = true;
          database = { type = "postgres"; socket = null; createDatabase = true; };
          settings.server.ROOT_URL = "http://localhost:3000";
        };
        assertions = lib.optionals guarded [
          { assertion = lib.sort builtins.lessThan (map (x: x.owner) requirements) == expectedOwners;
            message = "comparison/requirements: incomplete contributor coverage"; }
          { assertion = lib.all (r: builtins.elem port r.ports) requirements;
            message = "comparison/port: unsatisfied joint requirements"; }
          { assertion = builtins.hashString "sha256" text == saved.inputDigest;
            message = "comparison/source: changed since captured input"; }
          { assertion = plan.postgresql.port == port && plan.gitea.databasePort == clientPort;
            message = "comparison/plan: stale parent projection"; }
        ];
      };
    };
  };
  cfg = result.config;
  plan = if scenario == "stale-plan" then saved.plan else {
    postgresql.port = cfg.services.postgresql.settings.port;
    gitea.databasePort = cfg.services.gitea.database.port;
  };
  checks = map (a: if a.assertion then true else throw a.message) cfg.assertions;
in builtins.deepSeq checks {
  inherit plan;
  effective = {
    postgresql.port = cfg.services.postgresql.settings.port;
    gitea.databasePort = cfg.services.gitea.database.port;
    gitea.host = cfg.services.gitea.settings.database.HOST;
  };
  requirements = cfg.comparison.requirements;
  inputDigest = builtins.hashString "sha256" text;
}
