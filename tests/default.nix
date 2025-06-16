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
      import time

      def wait_for_ssh(machine):
        for i in range(500):
          print(f"Wait for ssh {i}/240")
          status, _ = machine.execute("sshpass -p gocubsgo ssh -o StrictHostKeyChecking=no cirros@192.168.1.2 echo hello")
          if status == 0:
            return True
          time.sleep(1)
        return False

      start_all()
      controllerVM.wait_for_unit("multi-user.target")

      controllerVM.succeed("cp /etc/cirros.img /nfs-root/")
      controllerVM.succeed("chmod 0666 /nfs-root/cirros.img")

      controllerVM.succeed("virt-admin -c virtchd:///system daemon-log-outputs \"2:journald 1:file:/var/log/libvirt/libvirtd.log\"")
      controllerVM.succeed("virt-admin -c virtchd:///system daemon-timeout --timeout 0")

      computeVM.succeed("virt-admin -c virtchd:///system daemon-log-outputs \"2:journald 1:file:/var/log/libvirt/libvirtd.log\"")
      computeVM.succeed("virt-admin -c virtchd:///system daemon-timeout --timeout 0")

      controllerVM.succeed("mkdir -p /var/lib/libvirt/storage-pools/nfs-share")
      computeVM.succeed("mkdir -p /var/lib/libvirt/storage-pools/nfs-share")

      controllerVM.succeed("ssh -o StrictHostKeyChecking=no computeVM echo")
      computeVM.succeed("ssh -o StrictHostKeyChecking=no controllerVM echo")

      ############ CHV Logging test  #######################

      # controllerVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"localhost\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      # controllerVM.succeed("virsh -c ch:///session pool-start nfs-share")

      # computeVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"controllerVM\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      # computeVM.succeed("virsh -c ch:///session pool-start nfs-share")

      # controllerVM.succeed("echo \"log_level = 1\" > /var/libvirt/ch/ch.conf")

      # controllerVM.succeed("virsh -c ch:///session create /etc/cirros-chv.xml")

      ############ CHV Hotplug test  #######################

      controllerVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"localhost\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      controllerVM.succeed("virsh -c ch:///session pool-start nfs-share")

      computeVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"controllerVM\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      computeVM.succeed("virsh -c ch:///session pool-start nfs-share")

      # Using define + start creates a "persistant" domain rather than a transient
      controllerVM.succeed("virsh -c ch:///session define /etc/cirros-chv.xml")
      controllerVM.succeed("virsh -c ch:///session start cirros")

      time.sleep(5)

      controllerVM.succeed("qemu-img create -f raw /tmp/disk.img 100M")
      controllerVM.succeed("virsh -c ch:///session attach-disk --domain cirros --target vdb --source /tmp/disk.img")

      time.sleep(5)

      controllerVM.succeed("virsh -c ch:///session detach-disk --domain cirros --target vdb")

      ############ CHV Live Migration #######################

      # controllerVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"localhost\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      # controllerVM.succeed("virsh -c ch:///session pool-start nfs-share")

      # computeVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"controllerVM\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
      # computeVM.succeed("virsh -c ch:///session pool-start nfs-share")

      # controllerVM.succeed("virsh -c ch:///session create /etc/cirros-chv.xml")

      # assert wait_for_ssh(controllerVM)

      # controllerVM.succeed("virsh -c ch:///session migrate --domain cirros --desturi ch+ssh://computeVM/session --live --verbose")

      # assert wait_for_ssh(computeVM)

      ############ QEMU Live Migration ######################

      # controllerVM.succeed("virsh -c \"qemu+tcp://controllerVM/system\" create /etc/cirros-qemu.xml")

      # controllerVM.succeed("virsh migrate --domain cirros --desturi qemu+tcp://computeVM/system --live --verbose")

      # computeVM.succeed("virsh dumpxml cirros")


      ############ non-Libvirt CHV Live Migration #######################
      # computeVM.succeed("screen -m -d cloud-hypervisor -vv --log-file /tmp/log --api-socket /tmp/api")
      # computeVM.succeed("screen -m -d ch-remote --api-socket=/tmp/api receive-migration tcp:0.0.0.0:41337")

      # controllerVM.succeed("screen -m -d cloud-hypervisor -vv --log-file /tmp/log --net \"tap=tap0,mac=18:ab:a5:f1:f7:56,ip=,mask=\" --kernel /etc/hypervisor-fw --disk path=/etc/cirros.img --cpus boot=1 --memory size=256M --serial file=/tmp/serial --api-socket=/tmp/api")
      # controllerVM.succeed("sleep 20")
      # controllerVM.succeed("ch-remote --api-socket=/tmp/api send-migration  tcp:computeVM:41337")
    '';
}
