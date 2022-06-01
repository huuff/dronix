{ config, pkgs, lib, ... }:
with lib;

# TODO: Runners
let
  cfg = config.servicesx.drone;
  providerModule = with types; submodule {
    options = {
      type = mkOption {
        type = enum [ "github" "gitea" "gitlab" ];
        default = null;
        description = "Type of provider, one of 'github', 'gitea', 'gitlab'";
      };

      clientId = mkOption {
        type = str;
        default = null;
        description = "OAuth Client ID";
      };

      server = mkOption {
        type = str;
        default = null;
        description = "Target server address";
      };

      clientSecretFile = mkOption {
        type = oneOf [ str path ];
        default = null;
        description = "Path to a file containing the OAuth Client Secret";
      };

      rpcSecretFile = mkOption {
        type = oneOf [ str path ];
        default = null;
        description = "Path to a file containing the shared secret between the Drone server and the runner";
      };

      host = mkOption {
        type = str;
        default = null;
        description = "Hostname or IP address of the Drone server";
      };

      # TODO: One for all servers? I won't provide TLS configuration for the Drone instance,
      # I think using TLS termination is much better
      protocol = mkOption {
        type = enum [ "http" "https" ];
        default = "http";
        description = "Protocol of the Drone server";
      };
    };
  };

  providerModuleToSystemdUnit = provider:
  let
    PROVIDER = toUpper provider.type;
  in {
    name = "drone-${provider.type}";
    value = {
      description = "Drone CI instance for ${provider.type}";

      # TODO: Secrets
      environment = {
        "DRONE_${PROVIDER}_CLIENT_ID" = provider.clientId;
        "DRONE_${PROVIDER}_SERVER" = provider.server;
        "DRONE_SERVER_HOST" = provider.host;
        "DRONE_SERVER_PROTO" = provider.protocol;
        };

      # TODO: Restart policy
      script = "${cfg.package}/bin/drone-server";
      wantedBy = [ "multi-user.target" ];
    };
  };
in
  {
    # TODO: Set up a user
    options.servicesx.drone = with types; {
      enable = mkEnableOption "Drone CI";

      package = mkOption {
        type = package;
        default = pkgs.drone;
        description = "Drone CI derivation";
      };

      providers = mkOption {
        type = listOf providerModule;
        default = [];
        description = "List of enabled providers (each one will be a separate instance)";
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        { assertion = length ( cfg.providers ) > 0; message = "You must specify at least one provider";}
      ]; 

      systemd.services = listToAttrs ( map providerModuleToSystemdUnit cfg.providers );
    };
  }
