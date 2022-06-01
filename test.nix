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
      imports = [ ./module.nix ];

      servicesx.drone = {
        enable = true;

        providers = [ {
          inherit host protocol port;

          type = "gitea";
          clientId = "test";
          address = "test";
          clientSecretFile = "test";
          rpcSecretFile = "test";
        } ];
      };
    };
  };

  testScript = ''
    gitea.wait_for_unit("drone-gitea")

    with subtest("API is running"):
      gitea.sleep(10)
      [ _, out ] = gitea.execute("journalctl -u drone-gitea")
      print(out)
      [ _, out] = gitea.execute('curl "${protocol}://${host}:${toString port}"')
      print(out)
      gitea.succeed('[ $(curl -Lso /dev/null -w "%{http_code}" "${protocol}://${host}:${toString port}") -eq 200 ]')
  '';
}
