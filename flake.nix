{
  description = "NixOS tests for libvirt development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # Make sure the submodule from a local libvirt checkout is populated.
    libvirt-src = {
      url = "git+file:/home/skober/repos/libvirt?submodules=1";
      # url = "git+https://github.com/cyberus-technology/libvirt?ref=gardenlinux&submodules=1";
      #url = "git+ssh://git@gitlab.vpn.cyberus-technology.de/shertrampf/libvirt.git?ref=ch-migrate-v11.4.0&submodules=1";
      flake = false;
    };
    cloud-hypervisor-src = {
      # url = "github:hertrste/cloud-hypervisor?ref=seccomp_http_api";
      url = "github:cyberus-technology/cloud-hypervisor?ref=gardenlinux";
      flake = false;
    };
    # Nix tooling to build cloud-hypervisor.
    crane.url = "github:ipetkov/crane/master";
    # Get proper Rust toolchain, independent of pkgs.rustc.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      libvirt-src,
      flake-utils,
      cloud-hypervisor-src,
      crane,
      rust-overlay,
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
              cloud-hypervisor = pkgs.callPackage ./chv.nix {
                inherit cloud-hypervisor-src;
                craneLib = crane.mkLib pkgs;
                rustToolchain = rust-bin.stable.latest.default;
                cloud-hypervisor-meta = prev.cloud-hypervisor.meta;
              };
            })
          ];
        };
        rust-bin = (rust-overlay.lib.mkRustBin { }) pkgs;
      in
      {
        formatter = pkgs.nixfmt-rfc-style;
        devShells.default = pkgs.mkShellNoCC {
          packages = with pkgs; [ ];
        };
        packages = {
          # Export of the overlay'ed package
          inherit (pkgs) cloud-hypervisor;
        };
        tests = pkgs.callPackage ./tests/default.nix { inherit libvirt-src; };
      }
    );
}
