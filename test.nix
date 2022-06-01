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

        providers = [
          {
            inherit host protocol port;

            type = "gitea";
            clientId = "test";
            address = "test";
            clientSecretFile = "test";
            rpcSecretFile = "test";
          } 
        ];
      };
    };
  };

  testScript = ''
    gitea.wait_for_unit("drone-gitea")

    with subtest("API is running"):
      gitea.succeed('[ $(curl -Lso /dev/null -w "%{http_code}" "${protocol}://${host}:${toString port}") -eq 200 ]')
  '';
}
