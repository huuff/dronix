{
  drone-runner-docker,
  ...
}:

{ config, pkgs, lib, ... }:
with lib;

let
  cfg = config.servicesx.drone;
  unitEnvFileDir = "/var/lib/drone/sysconfig";
  runnerModule = with types; submodule {
    options = {
      type = mkOption {
        type = enum [ "docker" ];
        default = null;
        description = "Type of runner, one of 'docker'";
      };
    };
  };
  serverModule = with types; submodule {
    options = {
      provider = {
        type = mkOption {
          type = enum [ "github" "gitea" "gitlab" ];
          default = null;
          description = "Type of provider, one of 'github', 'gitea', 'gitlab'";
        };

        address = mkOption {
          type = str;
          default = null;
          description = "Target server address";
        };

        clientId = mkOption {
          type = str;
          default = null;
          description = "OAuth Client ID";
        };

        clientSecretFile = mkOption {
          type = oneOf [ str path ];
          default = null;
          description = "Path to a file containing the OAuth Client Secret";
        };
      };

      rpcSecretFile = mkOption {
        type = oneOf [ str path ];
        default = null;
        description = "Path to a file containing the shared secret between the Drone server and the runner";
      };

      host = mkOption {
        type = str;
        default = "localhost";
        description = "Hostname or IP address of the Drone server";
      };

      port = mkOption {
        type = int;
        default = 8080;
        description = "Port on which the server will run";
      };

      # TODO: One for all servers? I won't provide TLS configuration for the Drone instance,
      # I think using TLS termination is much better
      protocol = mkOption {
        type = enum [ "http" "https" ];
        default = "http";
        description = "Protocol of the Drone server";
      };

      database = {
        driver = mkOption {
          type = enum [ "mysql" "postgres" "sqlite3" ];
          default = "sqlite3";
          description = "Database driver, one of mysql, postgres, sqlite3";
        };

        datasource = mkOption {
          type = oneOf [ str path ];
          default = "/var/lib/drone/data.sqlite";
          description = "Datasource url for the database";
        };
      };

      runners = mkOption {
        type = listOf runnerModule;
        default = [];
        description = "Runners that the server will use";
      };
    };
  };

  serverModuleToServerUnit = server:
  let
    providerName = server.provider.type;
    environmentFile = "${unitEnvFileDir}/${providerName}";
  in {
    name = "drone-${server.provider.type}";
    value = {
      description = "Drone CI instance for ${server.provider.type}";

      preStart =
        let 
          createEnvFile = pkgs.writeShellScript "drone-${providerName}-env" ''
            cat <<EOF | tee ${environmentFile}
              DRONE_${toUpper providerName}_CLIENT_ID="${server.provider.clientId}"
              DRONE_${toUpper providerName}_SERVER="${server.provider.address}"
              DRONE_${toUpper providerName}_CLIENT_SECRET="$(cat ${server.provider.clientSecretFile})"
              DRONE_SERVER_HOST="${server.host}"
              DRONE_SERVER_PROTO="${server.protocol}"
              DRONE_SERVER_PORT=":${toString server.port}"
              DRONE_DATABASE_DRIVER="${server.database.driver}"
              DRONE_DATABASE_DATASOURCE="${server.database.datasource}"
              DRONE_RPC_SECRET="$(cat ${server.rpcSecretFile})"
            EOF
            '';
        in "${createEnvFile}";
      

      script = ''
        ${cfg.package}/bin/drone-server
      '';
      bindsTo = [ "systemd-tmpfiles-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Restart = "always";
        User = cfg.user;
        # XXX: The `-` prefix means it might not exist yet
        EnvironmentFile = "-${environmentFile}";
      };
    };
  };
  runnerModuleToRunnerUnit = serverModule: runnerModule:
  let
    environmentFile = "${unitEnvFileDir}/runner-${runnerModule.type}";
    runnerPackage = if (runnerModule.type == "docker") 
        then drone-runner-docker  
        else throw "Unsupported runner type ${runnerModule.type}";
  in
  {
    name = "drone-runner-${runnerModule.type}";
    value = {
      description = "Drone CI runner instance for ${runnerModule.type} and ${serverModule.provider.type}";

      path = [ runnerPackage ];
      # TODO: Better dependencies among units!
      wants = [ "systemd-tmpfiles-setup.service" ];
      wantedBy = [ "multi-user.target" ]; 

      preStart =
        let 
          createEnvFile = pkgs.writeShellScript "drone-runner-${runnerModule.type}-env" ''
            cat <<EOF | tee ${environmentFile}
              DRONE_RPC_HOST="${serverModule.host}:${toString serverModule.port}"
              DRONE_RPC_PROTO="${serverModule.protocol}"
              DRONE_RPC_SECRET="$(cat ${serverModule.rpcSecretFile})"
            EOF
            '';
        in "${createEnvFile}";

      script = ''
        ${runnerPackage}/bin/drone-runner-${runnerModule.type}
      '';

      serviceConfig = {
        Restart = "always";
        User = cfg.user;
        EnvironmentFile = "-${environmentFile}";
      };
    };
  };

  serverModuleToRunnerUnits = serverModule: map (it: runnerModuleToRunnerUnit serverModule it) serverModule.runners;
in
  {
    options.servicesx.drone = with types; {
      enable = mkEnableOption "Drone CI";

      package = mkOption {
        type = package;
        default = pkgs.drone;
        description = "Drone CI derivation";
      };

      user = mkOption {
        type = str;
        default = "drone";
        description = "User under which to run drone";
      };

      group = mkOption {
        type = str;
        default = "drone";
        description = "Group to which the user will belong";
      };

      servers = mkOption {
        type = listOf serverModule;
        default = [];
        description = "List of enabled servers (each one will be a separate instance)";
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        { 
          assertion = length ( cfg.servers ) > 0;
          message = "You must specify at least one server";
        }
        {
          assertion =
          let
            portsUsed = map (it: it.port) cfg.servers;
          in
            length (unique (portsUsed)) == length (portsUsed);
          message = "Each server must use a different port";
        }
        {
          assertion = all (it: length (it.runners) > 0) cfg.servers;
          message = "Every server must have at least one runner";
        }
      ]; 

      systemd = {
        services = listToAttrs (map serverModuleToServerUnit cfg.servers)
                // listToAttrs (flatten (map serverModuleToRunnerUnits cfg.servers))
                ;

        tmpfiles.rules = 
        let
          serversUsingSqlite = filter (it: it.database.driver == "sqlite3") cfg.servers;
          baseDirs = map (it: dirOf it.database.datasource) serversUsingSqlite;
        in
          (map (databaseDir: "d ${databaseDir} 700 ${cfg.user} ${cfg.group} - -") baseDirs)
          ++ ["d ${unitEnvFileDir} 700 ${cfg.user} ${cfg.group} - -"] 
        ;
      };

      users = {
        groups.${cfg.group} = {};
        users.${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
        };
      };
    };
  }
