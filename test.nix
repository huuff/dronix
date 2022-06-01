{ pkgs, ... }:
pkgs.nixosTest {
  name = "drone";

  nodes = {
    gitea = { pkgs, ... }: {
      imports = [ ./module.nix ];

      servicesx.drone = {
        enable = true;

        providers = [ {
          type = "gitea";
          clientId = "test";
          server = "test";
          clientSecretFile = "test";
          rpcSecretFile = "test";
          host = "test";
          protocol = "http";
        } ];
      };
    };
  };

  testScript = ''
    gitea.wait_for_unit("drone-gitea")
  '';
}
