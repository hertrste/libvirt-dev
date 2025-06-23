{
  description = "NixOS tests for libvirt development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Make sure the submodule from a local libvirt checkout is populated.
    libvirt-src = {
      #url = "git+file:/home/skober/repos/libvirt?submodules=1";
      url = "git+https://github.com/cyberus-technology/libvirt?ref=gardenlinux-dev&submodules=1";
      #url = "git+ssh://git@gitlab.vpn.cyberus-technology.de/shertrampf/libvirt.git?ref=ch-migrate-v11.4.0&submodules=1";
      flake = false;
    };
    cloud-hypervisor = {
      # url = "github:hertrste/cloud-hypervisor?ref=seccomp_http_api";
      url = "github:phip1611/cloud-hypervisor?ref=network-fd-livemig";
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
      cloud-hypervisor,
      ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs-unstable = import nixpkgs-unstable { inherit system; };
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              # Live migration is supported since v43 of Cloud Hypervisor
              #cloud-hypervisor = pkgs-unstable.cloud-hypervisor;
              cloud-hypervisor = prev.callPackage ./chv.nix { src = cloud-hypervisor; };
            })
          ];
        };
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
