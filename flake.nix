{
  description = "NixOS module for Drone CI";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-22.05";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    packages.${system} = {
      drone-runner-docker = pkgs.callPackage ./docker-runner.nix {};
    };

    nixosModules = {
      drone = import ./module.nix;
    };

    nixosModule = self.nixosModules.drone;

    checks.${system} = {
      drone-gitea = import ./test.nix { inherit pkgs; };
    };
  };
}
