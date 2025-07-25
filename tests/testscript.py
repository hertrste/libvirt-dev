import time
import unittest

if 'start_all' not in globals():
    from nixos_test_stubs import start_all, computeVM, controllerVM # type: ignore

class LibvirtTests(unittest.TestCase):
  @classmethod
  def setUpClass(cls):
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

    controllerVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"localhost\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
    controllerVM.succeed("virsh -c ch:///session pool-start nfs-share")

    computeVM.succeed("virsh -c ch:///session pool-define-as --name \"nfs-share\" --type netfs --source-host \"controllerVM\" --source-path \"nfs-root\" --source-format \"nfs\" --target \"/var/lib/libvirt/storage-pools/nfs-share\"")
    computeVM.succeed("virsh -c ch:///session pool-start nfs-share")

  def setUp(self):
      print("setup")

  def tearDown(self):
      print("teardown")

      # Destroy and undefine all running and persistent domains
      controllerVM.execute("virsh -c ch:///session list --name | while read domain; do [[ -n \"$domain\" ]] && virsh -c ch:///session destroy \"$domain\"; done")
      controllerVM.execute("virsh -c ch:///session list --all --name | while read domain; do [[ -n \"$domain\" ]] && virsh -c ch:///session undefine \"$domain\"; done")
      computeVM.execute("virsh -c ch:///session list --name | while read domain; do [[ -n \"$domain\" ]] && virsh -c ch:///session destroy \"$domain\"; done")
      computeVM.execute("virsh -c ch:///session list --all --name | while read domain; do [[ -n \"$domain\" ]] && virsh -c ch:///session undefine \"$domain\"; done")
      print("fin teardown")

  def test_hotplug(self):
      # Using define + start creates a "persistant" domain rather than a transient
      controllerVM.succeed("virsh -c ch:///session define /etc/cirros-chv.xml")
      controllerVM.succeed("virsh -c ch:///session start cirros")

      assert wait_for_ssh(controllerVM)

      num_devices_old = number_of_devices(controllerVM)

      controllerVM.succeed("qemu-img create -f raw /tmp/disk.img 100M")
      controllerVM.succeed("virsh -c ch:///session attach-disk --domain cirros --target vdb --persistent --source /tmp/disk.img")

      controllerVM.succeed("virsh -c ch:///session attach-device --persistent cirros /etc/new_interface.xml")

      num_devices_new = number_of_devices(controllerVM)

      assert num_devices_new == num_devices_old + 2

      controllerVM.succeed("virsh -c ch:///session detach-disk --domain cirros --target vdb")
      controllerVM.succeed("virsh -c ch:///session detach-device cirros /etc/new_interface.xml")

      assert number_of_devices(controllerVM) == num_devices_old

  def test_libvirt_restart(self):
      """
      We test the restart of the libvirt daemon. A restart requires that
      we correctly re-attach to persistent domain, which can currently be
      running or shutdown.
      Currently, shutdown domains are detected as running which leads to
      problems when trying to interact with them.
      """
      # Using define + start creates a "persistant" domain rather than a transient
      controllerVM.succeed("virsh -c ch:///session define /etc/cirros-chv.xml")
      controllerVM.succeed("virsh -c ch:///session start cirros")

      assert wait_for_ssh(controllerVM)

      controllerVM.succeed("virsh -c ch:///session shutdown cirros")
      controllerVM.succeed("systemctl restart virtchd")

      controllerVM.succeed("virsh -c ch:///session list --all | grep 'shut off'")

      controllerVM.succeed("virsh -c ch:///session start cirros")
      controllerVM.succeed("systemctl restart virtchd")
      controllerVM.succeed("virsh -c ch:///session list | grep 'running'")

  def test_live_migration(self):
    """
    Test the live migration via virsh between 2 hosts. We want to use the
    "--p2p" flag as this is the one used by OpenStack Nova. Using "--p2p"
    results in another control flow of the migration, which is the one we
    want to test.
    We also hot-attach some devices before migrating, in order to cover
    proper migration of those devices.
    """

    controllerVM.succeed("virsh -c ch:///session define /etc/cirros-chv.xml")
    controllerVM.succeed("virsh -c ch:///session start cirros")

    assert wait_for_ssh(controllerVM)

    controllerVM.succeed("virsh -c ch:///session attach-device cirros /etc/new_interface.xml")
    controllerVM.succeed("qemu-img create -f raw /tmp/disk.img 100M")
    computeVM.succeed("qemu-img create -f raw /tmp/disk.img 100M")
    controllerVM.succeed("virsh -c ch:///session attach-disk --domain cirros --target vdb --persistent --source /tmp/disk.img")

    for i in range(5):
      # Explicitly use IP in desturi as this was already a problem in the past
      controllerVM.succeed("virsh -c ch:///session migrate --domain cirros --desturi ch+tcp://192.168.100.2/session --live --p2p")
      time.sleep(5)
      assert wait_for_ssh(computeVM)
      computeVM.succeed("virsh -c ch:///session migrate --domain cirros --desturi ch+tcp://controllerVM/session --live --p2p")
      time.sleep(5)
      assert wait_for_ssh(controllerVM)

def suite():
    suite = unittest.TestSuite()
    suite.addTest(LibvirtTests('test_hotplug'))
    suite.addTest(LibvirtTests('test_libvirt_restart'))
    suite.addTest(LibvirtTests('test_live_migration'))
    return suite

def wait_for_ssh(machine, user="cirros", password="gocubsgo", ip="192.168.1.2"):
  for i in range(500):
    print(f"Wait for ssh {i}/240")
    status, _ = ssh(machine, "echo hello")
    if status == 0:
      return True
    time.sleep(1)
  return False

def ssh(machine, cmd, user="cirros", password="gocubsgo", ip="192.168.1.2"):
  status, out = machine.execute(f"sshpass -p {password} ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no {user}@{ip} {cmd}")
  return status, out

def number_of_devices(machine):
  status, out = ssh(machine, "lspci | wc -l")
  assert status == 0
  return int(out)

runner = unittest.TextTestRunner()
runner.run(suite())
