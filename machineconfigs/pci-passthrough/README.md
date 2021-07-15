# Rebind SR-IOV Device Function to the vfio-pci module

## Description
The contents of this directory will allow specifying individual [Domain:Bus:Device.Function] to unbind from its existing driver/module and will rebind it to the vfio-pci driver/module.

This work is based off the Openshift documentation for OpenShift 4.8 and uses modified examples given in the documentation.

The process to do this is essentially:
1. Enable iommu on the node
2. Load the vfio-pci module
3. Unbind the pci device from its current driver/module
4. Bind the pci device to the vfio-pci driver/module

## Enable iommu
To use this, iommu must be enabled on the nodes. The OpenShift 4.8 documentation shows how to create a machineconfig file to accomplish this.

## Checking if a pci device supports SR-IOV

Use `lspci -D` to get the pci devices [Domain:Bus:Device.Function] identitfier.
```
# lspci -D
[..OUTPUT_TRUNCATED..]
0000:03:00.0 Ethernet controller: Intel Corporation I350 Gigabit Backplane Connection (rev 01)
0000:03:00.1 Ethernet controller: Intel Corporation I350 Gigabit Backplane Connection (rev 01)
0000:03:00.2 Ethernet controller: Intel Corporation I350 Gigabit Backplane Connection (rev 01)
0000:03:00.3 Ethernet controller: Intel Corporation I350 Gigabit Backplane Connection (rev 01)
[..OUTPUT_TRUNCATED..]
```

Once the identifier is known, check if the device supports SR-IOV using the `lspci -nnv -s` command.
```
# lspci -s 0000:03:00.0 -nnv | grep SR-IOV
	Capabilities: [160] Single Root I/O Virtualization (SR-IOV)
```
The above shows the device does indeed support SR-IOV and can be bound to the vfio-pci module.



## Load the vfio-pci module
This is done using a machineconfig file. But, as is done in the OpenShift documentation, we will write the configuration in a Butane configuration file and then convert it into a machineconfig file that is in a YAML format.

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

