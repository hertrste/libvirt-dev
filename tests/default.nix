{
  pkgs,
  libvirt-src,
}:
let
  virsh_ch_xml = ''
      <domain type='kvm' id='21050'>
      <name>cirros</name>
      <uuid>4eb6319a-4302-4407-9a56-802fc7e6a422</uuid>
      <memory unit='KiB'>262144</memory>
      <currentMemory unit='KiB'>262144</currentMemory>
      <vcpu placement='static'>1</vcpu>
      <os>
        <type arch='x86_64'>hvm</type>
        <kernel>/etc/hypervisor-fw</kernel>
        <boot dev='hd'/>
      </os>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <emulator>cloud-hypervisor</emulator>
        <disk type='file' device='disk'>
          <source file='/var/lib/libvirt/storage-pools/nfs-share/cirros.img'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <serial type='pty'>
          <source path='/dev/pts/2'/>
          <target port='0'/>
        </serial>
      </devices>
    </domain>
  '';
  virsh_qemu_xml = ''
      <domain type='kvm' id='21050'>
      <name>cirros</name>
      <uuid>4eb6319a-4302-4407-9a56-802fc7e6a422</uuid>
      <memory unit='KiB'>262144</memory>
      <currentMemory unit='KiB'>262144</currentMemory>
      <vcpu placement='static'>1</vcpu>
      <os>
        <type arch='x86_64'>hvm</type>
        <boot dev='hd'/>
      </os>
      <clock offset='utc'/>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <emulator>/run/current-system/sw/bin/qemu-system-x86_64</emulator>
        <disk type='file' device='disk'>
          <source file='/var/lib/libvirt/storage-pools/nfs-share/cirros.img'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <serial type='pty'>
          <source path='/dev/pts/2'/>
          <target port='0'/>
        </serial>
      </devices>
    </domain>
  '';
  image = pkgs.fetchurl {
    url = "https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img";
    hash = "sha256-B+RKc+VMlNmIAoUVQDwe12IFXgG4OnZ+3zwrOH94zgA=";
  };

  image_raw = pkgs.runCommand "image_raw" { } ''
    ${pkgs.qemu-utils}/bin/qemu-img convert -O raw ${image} $out
  '';

  common =
    { ... }:
    {
      virtualisation.libvirtd = {
        enable = true;
        sshProxy = false;
        package = pkgs.libvirt.overrideAttrs (old: {
          src = libvirt-src;
          doInstallCheck = false;
          doCheck = false;
        });
      };

      systemd.services.virtchd.wantedBy = [ "multi-user.target" ];
      systemd.sockets.virtstoraged.wantedBy = [ "sockets.target" ];

      # systemd.sockets.libvirtd-tcp = {
      #   enable = true;
      #   wantedBy = [ "sockets.target" ];
      # };

      virtualisation.libvirtd.extraConfig = ''
        listen_tls = 0
        listen_tcp = 1
        auth_tcp = "none"
      '';

      networking = {
        useDHCP = false;
        networkmanager.enable = false;
        useNetworkd = true;
        firewall.enable = false;
      };

      services.getty.autologinUser = "root";

      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin = "yes";
          PermitEmptyPasswords = "yes";
        };
      };

      security.pam.services.sshd.allowNullPassword = true;

      environment.systemPackages = [
        pkgs.cloud-hypervisor
        pkgs.qemu_kvm
      ];

      systemd.tmpfiles.settings =
        let
          chv-firmware = pkgs.fetchurl {
            url = "https://github.com/cloud-hypervisor/rust-hypervisor-firmware/releases/download/0.5.0/hypervisor-fw";
            hash = "sha256-Sgoel3No9rFdIZiiFr3t+aNQv15a4H4p5pU3PsFq2Vg=";
          };
        in
        {
          "10-chv" = {
            "/etc/hypervisor-fw" = {
              "L+" = {
                argument = "${chv-firmware}";
              };
            };
            "/etc/cirros.img" = {
              "C+" = {
                argument = "${image_raw}";
              };
            };
            "/etc/cirros-chv.xml" = {
              "C+" = {
                argument = "${pkgs.writeText "cirros.xml" virsh_ch_xml}";
              };
            };
            "/etc/cirros-qemu.xml" = {
              "C+" = {
                argument = "${pkgs.writeText "cirros.xml" virsh_qemu_xml}";
              };
            };
            "/var/log/libvirt/" = {
              D = {
                mode = "0755";
                user = "root";
              };
            };
            "/var/log/libvirt/ch" = {
              D = {
                mode = "0755";
                user = "root";
              };
            };
          };
        };
    };
in
pkgs.nixosTest {
  name = "Libvirt test";

  nodes.controllerVM =
    { ... }:
    {
      imports = [
        common
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
        common
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

      controllerVM.succeed("virsh -c ch:///session migrate --domain cirros --desturi ch+ssh://computeVM/session --live --verbose")

      # controllerVM.succeed("virsh -c \"qemu+tcp://controllerVM/system\" create /etc/cirros-qemu.xml")

      # controllerVM.succeed("virsh migrate --domain cirros --desturi qemu+tcp://computeVM/system --live --verbose")

      # computeVM.succeed("virsh dumpxml cirros")
    '';
}
