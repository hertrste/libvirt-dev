{ libvirt-src }:
{ pkgs, ... }:
let
  image = pkgs.fetchurl {
    url = "https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img";
    hash = "sha256-B+RKc+VMlNmIAoUVQDwe12IFXgG4OnZ+3zwrOH94zgA=";
  };
  image_ubuntu = pkgs.fetchurl {
    url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img";
    hash = "sha256-8WUtKdSX+3xiNDNwXJ/KZSXRMRsRKUoPSV7tVcdjnR8=";
  };

  pty = pkgs.writers.writePython3Bin "pty" { libraries = [ ]; } (builtins.readFile ../read_pty.py);

  read_pty = pkgs.writers.writePython3Bin "read_pty.py" { libraries = [ ]; } ''
  import os
  import sys
  import tty


  def set_terminal_mode(fd):
      try:
          # Raw mode - no input processing, character-by-character
          tty.setraw(fd)
          print("Set terminal to RAW mode")
          return True

      except Exception as e:
          print(f"Failed to set terminal mode 'raw': {e}")
          return False


  def readpty(path):
      import select

      try:
          with open(path, "w") as f:
              # set_terminal_mode(f)
              # Writing a null seems to trigger new output while not being
              # recognized as a newline or similar by the sender.
              f.write("\0")
              f.flush()

          epoll = select.epoll()

          with open(path, "rb") as f:
              os.set_blocking(f.fileno(), False)
              epoll.register(f.fileno(), select.EPOLLIN)
              poll_list = epoll.poll(1)
              data = bytearray()
              for _ in poll_list:
                  data += f.read()
              epoll.unregister(f.fileno())
              epoll.close()
              print(f"Got data bytes: {len(data)}")
              return data.decode("utf-8", errors="ignore")
      except Exception as exc:
          print(exc)


  if __name__ == "__main__":
      print(readpty(sys.argv[1]))
  '';

  image_raw = pkgs.runCommand "image_raw" { } ''
    ${pkgs.qemu-utils}/bin/qemu-img convert -O raw ${image} $out
  '';
  ubuntu_raw = pkgs.runCommand "image_raw" { } ''
    ${pkgs.qemu-utils}/bin/qemu-img convert -O raw ${image_ubuntu} $out
  '';
  # Network interface definition for later usage:
  # <interface type='ethernet'>
  #   <mac address='52:54:00:e5:b8:ef'/>
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
        <interface type='ethernet'>
          <mac address='52:54:00:e5:b8:ef'/>
          <target dev='vnet0'/>
          <model type='virtio'/>
          <driver queues='1'/>
        </interface>
        <serial type='pty'>
          <source path='/dev/pts/2'/>
          <target port='0'/>
        </serial>
      </devices>
    </domain>
  '';
  virsh_ch_xml_ubuntu = ''
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
          <source file='/var/lib/libvirt/storage-pools/nfs-share/ubuntu.img'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <interface type='ethernet'>
          <mac address='52:54:00:e5:b8:ef'/>
          <target dev='vnet0'/>
          <model type='virtio'/>
          <driver queues='1'/>
        </interface>
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
        <type arch='x86_64' machine='pc-q35-6.2'>hvm</type>
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

  new_disk = ''
    <disk type='file' device='disk'>
      <source file='/tmp/disk.img'/>
      <target dev='vdb' bus='virtio'/>
    </disk>
  '';
  new_interface = ''
    <interface type='ethernet'>
      <mac address='52:54:00:e5:b8:dd'/>
      <target dev='tap0'/>
      <model type='virtio'/>
      <driver queues='1'/>
    </interface>
  '';
in
{
  virtualisation.libvirtd = {
    enable = true;
    sshProxy = false;
    package = pkgs.libvirt.overrideAttrs (old: {
      src = libvirt-src;
      debug = true;
      doInstallCheck = false;
      doCheck = false;
      patches = [
        ../patches/libvirt/0001-meson-patch-in-an-install-prefix-for-building-on-nix.patch
        ../patches/libvirt/0002-substitute-zfs-and-zpool-commands.patch
      ];
      # Reduce files needed to compile. We cut the build-time in half.
      mesonFlags = old.mesonFlags ++ [
        # Disabling tests: 1500 -> 1200
        "-Dtests=disabled"
        "-Dexpensive_tests=disabled"
        # Disabling docs: 1200 -> 800
        "-Ddocs=disabled"
        # Disabling unneeded backends: 800 -> 685
        "-Ddriver_ch=enabled"
        "-Ddriver_qemu=enabled"
        "-Ddriver_bhyve=disabled"
        "-Ddriver_esx=disabled"
        "-Ddriver_hyperv=disabled"
        "-Ddriver_libxl=disabled"
        "-Ddriver_lxc=disabled"
        "-Ddriver_openvz=disabled"
        "-Ddriver_secrets=disabled"
        "-Ddriver_vbox=disabled"
        "-Ddriver_vmware=disabled"
        "-Ddriver_vz=disabled"
      ];
    });
  };

  virtualisation.diskSize = 4096;

  systemd.services.virtstoraged.path = [ pkgs.mount ];

  systemd.services.virtchd.wantedBy = [ "multi-user.target" ];
  systemd.services.virtchd.path = [ pkgs.openssh ];
  systemd.sockets.virtproxyd-tcp.wantedBy = [ "sockets.target" ];
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
        enable = true;
        matchConfig.Name = "br0";
        networkConfig = {
          Description = "Main Bridge";
          DHCPServer = "yes";
        };

        dhcpServerStaticLeases = [
          {
            Address = "192.168.1.2";
            MACAddress = "52:54:00:e5:b8:ef";
          }
          {
            Address = "192.168.1.3";
            MACAddress = "52:54:00:e5:b8:ee";
          }
        ];

        # DHCP server settings
        dhcpServerConfig = {
          PoolOffset = 2;
          PoolSize = 10;
          EmitDNS = false;
          # DNS = [
          #   "8.8.8.8"
          #   "8.8.4.4"
          # ]; # DNS servers to offer
          EmitRouter = false;
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
      # "10-vmtap0" = {
      #   matchConfig.Name = "vmtap*";
      #   networkConfig.Bridge = "br0";
      # };
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
    pkgs.mount
    pkgs.gdb
    pkgs.screen
    pkgs.tunctl
    pkgs.lsof
    pkgs.python3
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
        "/etc/read_pty.py" = {
          "L+" = {
            argument = "${read_pty}";
          };
        };
        "/etc/pty.py" = {
          "L+" = {
            argument = "${pty}";
          };
        };
        "/etc/cirros.img" = {
          "C+" = {
            argument = "${image_raw}";
          };
        };
        "/etc/ubuntu.img" = {
          "C+" = {
            argument = "${image_ubuntu}";
          };
        };
        "/etc/cirros.qcow2" = {
          "C+" = {
            argument = "${image}";
          };
        };
        "/etc/cirros-chv.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "cirros.xml" virsh_ch_xml}";
          };
        };
        "/etc/cirros-chv-ubuntu.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "ubuntu.xml" virsh_ch_xml_ubuntu}";
          };
        };
        "/etc/cirros-qemu.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "cirros.xml" virsh_qemu_xml}";
          };
        };
        "/etc/new_disk.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "new_disk.xml" new_disk}";
          };
        };
        "/etc/new_interface.xml" = {
          "C+" = {
            argument = "${pkgs.writeText "new_interface.xml" new_interface}";
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
