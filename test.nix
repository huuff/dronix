{ pkgs, ... }:
let
  host = "localhost";
  protocol = "http";
  port = 8081;
in
pkgs.nixosTest {
  name = "drone";

  nodes = {
    gitea = { pkgs, ... }: {
      imports = [ (import ./module.nix {
        drone-runner-docker = pkgs.callPackage ./docker-runner.nix {};
      })];

      servicesx.drone = {
        enable = true;

        servers = [
          {
            inherit host protocol port;

            provider = {
              type = "gitea";
              clientId = "test";
              address = "test";
              clientSecretFile = pkgs.writeText "client-secret" "test";
            };

            rpcSecretFile = pkgs.writeText "rpc-secret" "test";

            runners = [
              { type = "docker"; }
            ];
          } 
        ];
      };
    };
  };

  testScript = ''
    gitea.wait_for_unit("drone-gitea")
    gitea.sleep(1)

    with subtest("API is running"):
      gitea.succeed('[ $(curl -Lso /dev/null -w "%{http_code}" "${protocol}://${host}:${toString port}") -eq 200 ]')


    gitea.wait_for_unit("drone-gitea-runner-docker")
  '';
}
