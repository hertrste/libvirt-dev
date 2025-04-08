{ libvirt-src }:
{ pkgs, ... }:
let
  image = pkgs.fetchurl {
    url = "https://download.cirros-cloud.net/0.6.3/cirros-0.6.3-x86_64-disk.img";
    hash = "sha256-fWNVhSrrbbzRkbzafNdPFTbP5cv4oQSVpyg6g5bkt1s=";
  };

  image_raw = pkgs.runCommand "image_raw" { } ''
    ${pkgs.qemu-utils}/bin/qemu-img convert -O raw ${image} $out
  '';
    # Network interface definition for later usage:
    # <interface type='ethernet'>
    #   <target dev='vnet0'/>
    #   <model type='virtio'/>
    #   <driver queues='1'/>
    # </interface>
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
in
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

  systemd.network = {
    enable = true;
    wait-online.enable = false;

    netdevs = {
      "10-br0" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br0";
        };
      };
    };

    networks = {
      # Bridge interface configuration
      "10-br0" = {
        matchConfig.Name = "br0";
        networkConfig = {
          Description = "Main Bridge";
          DHCPServer = "yes"; # Enable DHCP server on this interface
        };

        # DHCP server settings
        dhcpServerConfig = {
          PoolOffset = 100;
          PoolSize = 1;
          EmitDNS = true;
          DNS = [
            "8.8.8.8"
            "8.8.4.4"
          ]; # DNS servers to offer
          EmitRouter = true;
        };

        # Static IP configuration for the bridge itself
        address = [
          "192.168.1.1/24"
        ];
      };
      "10-vnet0" = {
        matchConfig.Name = "vnet*";
        networkConfig.Bridge = "br0";
      };
    };
  };

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
    pkgs.bridge-utils
    pkgs.screen
    pkgs.jq
    pkgs.sshpass
  ];

  systemd.tmpfiles.settings =
    let
      chv-firmware = pkgs.fetchurl {
        url = "https://github.com/cloud-hypervisor/rust-hypervisor-firmware/releases/download/0.5.0/hypervisor-fw";
        hash = "sha256-Sgoel3No9rFdIZiiFr3t+aNQv15a4H4p5pU3PsFq2Vg=";
        # url = "https://github.com/cloud-hypervisor/edk2/releases/download/ch-a54f262b09/CLOUDHV.fd";
        # hash = "sha256-BiTAbF0Hy47+OIBokM5wdsQcCQLy/NWyN28QcDPjIis=";
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
}
