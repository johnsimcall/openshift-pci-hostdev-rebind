#! /bin/bash

pci_file=$1

: ${pci_file:=/etc/sysconfig/vfio-pci-devices}

[[ ! -f $pci_file ]] && exit

echo "Hostname is '$(hostname)'"

while read HOST DBDF
do
  # Check if it should rebind on this host.
  [[ $HOST == $(hostname) || $HOST == DEFAULT ]] \
  && {
    echo "binding: $DBDF"

    # Check if device supports SR-IOV
    lspci -D -s $DBDF -nnv | grep -q SR-IOV \
    && {
      # Get Current driver, Vendor and Device
      current_drv="$( lspci -D -s $DBDF -nnk | sed -n 's/\s*Kernel driver in use: \(.*\)/\1/p' )"
      vendor="$( sed 's/^0x//' /sys/bus/pci/devices/$DBDF/vendor )"
      device="$( sed 's/^0x//' /sys/bus/pci/devices/$DBDF/device )"

      # Unbind from the current driver if needed
      [[ $current_drv != vfio-pci ]] \
      && {
        echo $DBDF > /sys/bus/pci/drivers/$current_drv/unbind
      } || { 
        echo "$DBDF already bound to vfio-pci, skipping"
      }

      # Bind to the new driver
      echo $vendor $device > /sys/bus/pci/drivers/vfio-pci/new_id

      # Verify binding worked
      new_drv="$( lspci -D -s $DBDF -nnk | sed -n 's/\s*Kernel driver in use: \(.*\)/\1/p' )"
      [[ $new_drv == vfio-pci ]] \
      && echo "$DBDF successfuly bound to vfio-pci" \
      || echo "$DBDF failed to bind to vfio-pci" 
    } || {
      echo "$DBDF does not support SR-IOV, not attempting to bind"
    }

  } || {

  echo "No host match, skip binding of $DBDF to vfio-pci"
 }

done < <( sed -e '/^\s*$/d' -e '/^\s*[#;]/d' $pci_file )

