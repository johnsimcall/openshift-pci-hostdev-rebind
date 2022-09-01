#!/bin/bash
# This script will change (rebind) the kernel driver assigned to a PCI device
# more info at these links
# https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-bus-pci
# https://kubevirt.io/user-guide/virtual_machines/host-devices/
# https://docs.openshift.com/container-platform/4.10/virt/virtual_machines/advanced_vm_management/virt-configuring-pci-passthrough.html

# Check for a config file override, or use the default
pci_file=$1
: ${pci_file:=/etc/sysconfig/vfio-pci-devices}

# Check that the config file exists
if [[ -f $pci_file ]]; then
  echo "Reading $pci_file for host/device pairs"
else
  echo "Error: can't find config file at $pci_file" ; exit 1
fi

echo "Hostname is '$(hostname)'"
while read HOST DBDF  # DBDF is the PCI device's Domain.Bus.Device.Function identifier
do
  if [[ $HOST != $(hostname) && $HOST != ALL ]]; then
    echo "No host match, skip binding of $DBDF to vfio-pci on $HOST"
  else
    echo "Found host/device match, rebinding $DBDF to vfio-pci on $HOST"

    vendor=$(sed 's/^0x//' /sys/bus/pci/devices/$DBDF/vendor)
    device=$(sed 's/^0x//' /sys/bus/pci/devices/$DBDF/device)
    current_drv=$(lspci -ks $DBDF | awk -F": " '/Kernel driver in use:/ {print $2}')

    if [[ $current_drv != vfio-pci ]]; then
      echo $DBDF > /sys/bus/pci/drivers/$current_drv/unbind
      #jobbler method
      #echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id

      #kubevirt method
      echo vfio-pci > /sys/bus/pci/devices/$DBDF/driver_override
      echo $DBDF    > /sys/bus/pci/drivers/vfio-pci/bind
    else
      echo "$DBDF already bound to vfio-pci, skipping"
    fi

    # Verify binding worked
    new_drv=$(lspci -ks $DBDF | awk -F": " '/Kernel driver in use:/ {print $2}')
    if [[ $new_drv = vfio-pci ]]; then
      echo "$DBDF successfuly bound to vfio-pci on $HOST"
    else
      echo "$DBDF failed to bind to vfio-pci on $HOST"
    fi
  fi
done < <(sed -e '/^\s*$/d' -e '/^\s*[#;]/d' $pci_file)
#This ^^^ gnarly command/process substitution strips empty lines and comments from the $pci_file and sends what's left into the `while read HOST DBDF` command
