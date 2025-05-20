{
  description = "NixOS tests for libvirt development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Make sure the submodule from a local libvirt checkout is populated.
    libvirt-src = {
      # url = "git+file:/home/skober/repos/libvirt?submodules=1";
      url = "git+ssh://git@gitlab.vpn.cyberus-technology.de/shertrampf/libvirt.git?ref=ch-migrate-v11.4.0&submodules=1";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      libvirt-src,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs-unstable = import nixpkgs-unstable { inherit system; };
        pkgs = import nixpkgs { inherit system; overlays = [
          (final: prev: {
            # Live migration is supported since v43 of Cloud Hypervisor
            cloud-hypervisor = pkgs-unstable.cloud-hypervisor;
          })
        ]; };
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
