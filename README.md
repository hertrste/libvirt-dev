# Libvirt Nixos Tests

A small collection of NixOS tests to check certain Libvirt features.

The tests are meant to simplify development regarding Libvirt.

## Usage

Prerequisites:

* `nix` must be installed on your system

Checkout the repository:

```shell
git clone https://github.com/hertrste/libvirt-dev.git
cd libvirt-dev
```

To execute the tests in an interactive fashion use the following command:

```shell
nix build .#tests.x86_64-linux.driverInteractive && ./result/bin/nixos-test-driver
```

A python shell will be entered and by executing `test_script()` the test
execution will start.

In the QEMU VM windows, you can interact with the Cloud Hypervisor Libvirt daemon via:

```shell
virsh -c ch:///session <cmd>

# For example

virsh -c ch:///session list
```

## Tests

Test descriptions are in python and located under `tests/default.nix`. For
simplicity, unnecessary tests are simply commented out.
