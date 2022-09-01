# Rebind SR-IOV Device Function to the vfio-pci module

## Description
TODO: Refactor this documentation to make it clear that there are two paths possible. The first path, described in OpenShift documentation, is to reassign entire PCI devices to the vfio-pci kernel module via config files in /etc/modules-load.d/... and /etc/modprobe.d/... This path assumes the PCI device's driver was built as a kernel module. The second path is to reassign PCI devices, or SRIOV functions, while the server is running. This path addresses situations where PCI devices are claimed (bind/bound) by a particular kernel module, but need to be reassigned to the vfio-pci module. This document focuses on the second path which is documented in KubeVirt documentation.

These scripts allow individual PCI devices [Domain:Bus:Device.Function] to unbind from their default kernel driver/module and rebind to the vfio-pci driver/module. I need a PCI Express card with USB ports on it to unbind from `xhci_hcd` and bind to vfio-pci so that the card can be assigned to a VirtualMachine. `xhci_hcd` is built-into the RHEL kernel which means any kernel cmdline arguments like rd.blacklist=xhci_hcd don't work. I also don't want all of the USB3 ports to stop working

This work is based off https://github.com/jobbler/openshift-goods/

The process to do this is essentially:
1. Enable iommu on the node
2. Load the vfio-pci module
3. Unbind the pci device from its current driver/module
4. Bind the pci device to the vfio-pci driver/module

## Enable iommu
To use this, IOMMU must be enabled on the nodes. The [OpenShift 4.10 documentation](https://docs.openshift.com/container-platform/4.10/virt/virtual_machines/advanced_vm_management/virt-configuring-pci-passthrough.html) shows how to create a machineconfig file to accomplish this.

## Identify the pci device
Use `lspci -Dnn` to get the pci devices [Domain:Bus:Device.Function] identitfier.
```
# lspci -Dnn | grep USB
0000:00:14.0 USB controller [0c03]: Intel Corporation C610/X99 series chipset USB xHCI Host Controller [8086:8d31] (rev 05)
0000:00:1a.0 USB controller [0c03]: Intel Corporation C610/X99 series chipset USB Enhanced Host Controller #2 [8086:8d2d] (rev 05)
0000:00:1d.0 USB controller [0c03]: Intel Corporation C610/X99 series chipset USB Enhanced Host Controller #1 [8086:8d26] (rev 05)
0000:05:00.0 USB controller [0c03]: VIA Technologies, Inc. VL805 USB 3.0 Host Controller [1106:3483] (rev 01)
```
I am targeting the "VIA Technologies, Inc. VL805 USB 3.0" device. That device's VENDOR:DEVICE ID is 1106:3483.


## Load the vfio-pci module
Because the VFIO-PCI driver/module doesn't automatically bind to any hardware devices, it doesn't get loaded by default. This means that we have to load the driver/module ourselves. Instead of running `modprobe vfio-pci`, we can just add the name of the module to a .conf file under `/etc/modules-load.d/`. Telling vfio-pci which  hardware it will bind to is done by adding the "id=..." option when loading the module. Instead of typing `modprobe vfio-pci ids=1106:3483` we'll identify the hardware in `/etc/modprobe.d/vfio-pci.conf` file. Adding these two files to OpenShift nodes is done by creating a `butane` YAML file, converting it to MachineConfig format, and uploading it to the cluster.

This is a modified version of the file given in the documentation.
The example in the documentation allows an entire pci adapter to bind to the vfio-pci driver/module.
This is because it creates a file in the /etc/modprobe.d directory containing the pci [Vendor:Device] to bind to when loading the vfio-pci module.

Note: If the nodes initial ramdisk contains the adapters driver, it may need to be deny listed on the kernel line.
This can be done by adding `rd.driver.blacklist=module_name` to the kernel boot line.
This can be added using the same machineconfig that enables iommu.
Keep in mind binding entire adapters in this way will probably bind all afapters with teh same [Vendor:Device] identifier.

The 100-worker-vfiopci.bu butane file will only create the file that will cause the vfio-pci module to load at boot.
To apply the file, first convert the butane file to a YAML file than apply it using the `oc` command. The nodes will reboot when applying the machineconf.
```
butane 100-worker-vfiopci.bu -o 100-worker-vfiopci.yaml
oc apply -f 100-worker-vfiopci.yaml
```

## Unbinding and rebinding the device to the vfio-driver
The `rebind-to-vfiopci.sh` script will unbind a pci device from its current module and rebind it to the vfio-pci module.
It takes a file as input. If no file is specified, it defaults to `/etc/sysconfig/vfio-pci-device`.
The file specifies which node and pci device should be rebound to the vfio-pci module.

This file is in the format of `Node Domain:Bus:Device.Function`. Node can also be `DEFAULT` and will cause the pci device to unbind/rebind on all nodes defined as a worker.

For example, the following will bind pci device 0000:03:00.1 only on worker-0, 0000:03:00.2 only on worker-1, but 0000:03:00.0 on all nodes defined as workers.
```
worker-0 0000:03:00.1
worker-1 0000:03:00.2
DEFAULT  0000:03:00.0
```

## Creating a systemd service to rebind at boot
The `100-worker-vfiopci-rebind.bu` butane file will create a machineconfig file that will create the `rebind-to-vfiopci.sh` script, create a systemd service to run the script at boot, and create the configuration file for it to use.

The file must be modified for the pci devices that need to be bound to the vfio-pci module.
Modify the contents section of the file to contain the correct entries.
```
[..OUTPUT TRUNCATED..]
  - path: /etc/sysconfig/vfio-pci-devices
    mode: 0644
    overwrite: true
    contents:
      inline: |
        worker-0 0000:03:00.1
        worker-1 0000:03:00.2
        DEFAULT  0000:03:00.0
```

Create the YAML file from the butane file.
Since the butane file uses the rebind-to-vfiopci.sh as an include file, the `--files-dir` option must be specified.
```
butane-amd64 --files-dir /home/joherr/pearl ../100-worker-vfiopci-rebind.bu -o 100-worker-vfiopci-rebind.yaml
```

Apply the machineconfig YAML. The nodes will reboot as the configuration is made.
```
oc apply -f 100-worker-vfiopci-rebind.yaml
```

## Check for success

Log into the nodes and check the status of the vfio-rebind service.
The log output should show if the binding worked correctly.
```
# systemctl status vfio-rebind
● vfio-rebind.service - Rebinds pci devices to the vfio-pci driver.
   Loaded: loaded (/etc/systemd/system/vfio-rebind.service; enabled; vendor preset: disabled)
   Active: active (exited) since Thu 2021-07-15 18:47:09 UTC; 1h 56min ago
 Main PID: 2178 (code=exited, status=0/SUCCESS)
    Tasks: 0 (limit: 823049)
   Memory: 0B
      CPU: 0
   CGroup: /system.slice/vfio-rebind.service

Jul 15 18:47:09 worker-0 systemd[1]: Starting Rebinds pci devices to the vfio-pci driver....
Jul 15 18:47:09 worker-0 rebind-to-vfiopci.sh[2178]: Hostname is 'worker-0'
Jul 15 18:47:09 worker-0 rebind-to-vfiopci.sh[2178]: binding: 0000:03:00.1
Jul 15 18:47:09 worker-0 rebind-to-vfiopci.sh[2178]: 0000:03:00.1 successfuly bound to vfio-pci
Jul 15 18:47:09 worker-0 rebind-to-vfiopci.sh[2178]: No host match, skip binding of 0000:03:00.>
Jul 15 18:47:09 worker-0 rebind-to-vfiopci.sh[2178]: binding: 0000:03:00.0
Jul 15 18:47:09 worker-0 rebind-to-vfiopci.sh[2178]: 0000:03:00.0 successfuly bound to vfio-pci
Jul 15 18:47:09 worker-0 systemd[1]: Started Rebinds pci devices to the vfio-pci driver..
```

Verify the driver is truly bound to the pci device.
Use the `lspci -nnk -s` command and see which kernel driver is in use, it should report vfio-pci.
```
# lspci -s 0000:03:00.0 -nnk
03:00.0 Ethernet controller [0200]: Intel Corporation I350 Gigabit Backplane Connection [8086:1523] (rev 01)
	Subsystem: Intel Corporation 1GbE 4P I350 Mezz [8086:1f52]
	Kernel driver in use: vfio-pci
	Kernel modules: igb
```

