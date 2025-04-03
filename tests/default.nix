{
  pkgs,
  libvirt-src,
}:
pkgs.nixosTest {
  name = "Libvirt test";

  nodes.controllerVM =
    { ... }:
    {
      imports = [
        (import ./common.nix { inherit libvirt-src; })
        ../modules/nfs-host.nix
      ];

      virtualisation = {
        cores = 2;
        memorySize = 2048;
        interfaces = {
          eth1 = {
            vlan = 1;
          };
        };
      };

      networking.extraHosts = ''
        192.168.100.2 computeVM computeVM.local
      '';

      systemd.network = {
        enable = true;
        wait-online.enable = false;

        networks = {
          eth0 = {
            matchConfig.Name = [ "eth0" ];
            networkConfig = {
              DHCP = "yes";
            };
          };
          eth1 = {
            matchConfig.Name = [ "eth1" ];
            networkConfig = {
              Address = "192.168.100.1/24";
              Gateway = "192.168.100.1";
              DNS = "8.8.8.8";
            };
          };
        };
      };
    };

  nodes.computeVM =
    { ... }:
    {
      imports = [
        (import ./common.nix { inherit libvirt-src; })
        ../modules/nfs-client.nix
      ];

      networking.extraHosts = ''
        192.168.100.1 controllerVM controllerVM.local
      '';

      virtualisation = {
        cores = 2;
        memorySize = 2048;
        interfaces = {
          eth1 = {
            vlan = 1;
          };
        };
      };

      livemig.nfs.host = "192.168.100.1";

      systemd.network = {
        enable = true;
        wait-online.enable = false;

        networks = {
          eth0 = {
            matchConfig.Name = [ "eth0" ];
            networkConfig = {
              DHCP = "yes";
            };
          };
          eth1 = {
            matchConfig.Name = [ "eth1" ];
            networkConfig = {
              Address = "192.168.100.2/24";
              Gateway = "192.168.100.1";
              DNS = "8.8.8.8";
            };
          };
        };
      };
    };

  testScript =
    { ... }:
    ''
      start_all()
      controllerVM.wait_for_unit("multi-user.target")

      controllerVM.succeed("cp /etc/cirros.img /nfs-root/")
      controllerVM.succeed("chmod 0666 /nfs-root/cirros.img")

      controllerVM.succeed("virt-admin -c virtchd:///system daemon-log-outputs \"2:journald 1:file:/var/log/libvirt/libvirtd.log\"")
      controllerVM.succeed("virt-admin -c virtchd:///system daemon-timeout --timeout 0")

      computeVM.succeed("virt-admin -c virtchd:///system daemon-log-outputs \"2:journald 1:file:/var/log/libvirt/libvirtd.log\"")
      computeVM.succeed("virt-admin -c virtchd:///system daemon-timeout --timeout 0")

      controllerVM.succeed("mkdir -p /var/lib/libvirt/storage-pools/nfs-share")
      controllerVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"localhost\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      controllerVM.succeed("virsh -c ch:///session pool-start nfs-share")

      computeVM.succeed("mkdir -p /var/lib/libvirt/storage-pools/nfs-share")
      computeVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"controllerVM\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      computeVM.succeed("virsh -c ch:///session pool-start nfs-share")

      controllerVM.succeed("virsh -c ch:///session create /etc/cirros-chv.xml")

      # Add to list of known hosts so Libvirt can connect freely via ssh afterwards
      controllerVM.succeed("ssh -o StrictHostKeyChecking=no computeVM echo")
      computeVM.succeed("ssh -o StrictHostKeyChecking=no controllerVM echo")

      controllerVM.succeed("sleep 30 && virsh -c ch:///session migrate --domain cirros --desturi ch+ssh://computeVM/session --live --verbose")

      # controllerVM.succeed("virsh -c \"qemu+tcp://controllerVM/system\" create /etc/cirros-qemu.xml")

      # controllerVM.succeed("virsh migrate --domain cirros --desturi qemu+tcp://computeVM/system --live --verbose")

      # computeVM.succeed("virsh dumpxml cirros")
    '';
}
