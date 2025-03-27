{
  description = "NixOS tests for libvirt development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
    # Make sure the submodule from a local libvirt checkout is populated.
    libvirt-src = {
      url = "git+file:/home/skober/repos/libvirt?submodules=1";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      libvirt-src,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        formatter = pkgs.nixfmt-rfc-style;
        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [ ];
        };

        tests = pkgs.callPackage ./tests/default.nix { inherit libvirt-src; };
      }
    );
}
