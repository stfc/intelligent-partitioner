#!/bin/bash

TOOLS=$(dirname $0)

#Try to work out which physical disk the boot device is
boot_disk=$(grep boot /etc/mtab | grep -o sd[a-z])

NUMBER_OF_PARTITIONS=3
LABEL_PREFIX='data'

#Try to autodetect RAID parameters
source $TOOLS/detect-raid-parameters.sh

if [[ "$RAID_LEVEL" == "" ]]; then
  echo "ERROR: RAID Level was not detected"
  exit 1
fi

if [[ "$RAID_STRIPE_SIZE" == "" ]]; then
  echo "ERROR: RAID Stripe Size was not detected"
  exit 1
fi

if [[ "$RAID_DRIVE_COUNT" == "" ]]; then
  echo "ERROR: RAID Drive Count was not detected"
  exit 1
fi

# Discount parity drives
RAID_DRIVE_COUNT=$(($RAID_DRIVE_COUNT - ($RAID_LEVEL - 4)))

# Assemble XFS creation options
XFS_OPTS="-f -l version=2 -i size=1024 -n size=65536 -d su=${RAID_STRIPE_SIZE}k,sw=${RAID_DRIVE_COUNT}"

echo " INFO: XFS creation parameters have been set to '$XFS_OPTS'"

function pause {
  echo -n " INFO: Pausing for 5 seconds: "
  for i in 5 4 3 2 1; do
    echo -n "$i.."
    sleep 1
  done
  echo "0"
}

if [[ ! -z $boot_disk ]]; then
  #Find physical disks that aren't the boot disk
  data_disk="$(grep -o sd[a-z]$ /proc/partitions | grep -v $boot_disk)"

  #Count found disks
  data_disk_count="$(echo $data_disk | wc -w)"

  echo " INFO: Boot disk appears to be $boot_disk"

  #Only proceed if we find one data disk, assume that anything else is an error
  if [[ $data_disk_count -eq 1 ]]; then
    echo " INFO: Data disk appears to be $data_disk"

    boot_disk_size=$(parted /dev/$boot_disk unit MB print | grep ^Disk | grep -o '[0-9]\+')
    data_disk_size=$(parted /dev/$data_disk unit MB print | grep ^Disk | grep -o '[0-9]\+')

    echo " INFO: Boot disk appears to be ${boot_disk_size}MB in size"
    echo " INFO: Data disk appears to be ${data_disk_size}MB in size"

    #Don't proceed unless data disk is the big one, this is a failsafe in-case we somehow chose the OS disks
    if [[ $boot_disk_size -lt $data_disk_size ]]; then
      echo "   OK: Boot disk is smaller than data disk, continuing."

      #Calculate partiton size, we are ok with rounding errors at the MB level
      partition_size=$(($data_disk_size / $NUMBER_OF_PARTITIONS))

      echo " INFO: Will make $NUMBER_OF_PARTITIONS partitions of ${partition_size}MB, Ok to continue? (yes)"
      s=""
      echo -n "> "
      read s

      if [[ $s == "yes" ]]; then
        # Re-create partition table
        parted -s /dev/$data_disk mklabel gpt

        # Create partitions
        for i in $(seq 1 $NUMBER_OF_PARTITIONS); do
          p_start=$((partition_size * ($i - 1)))
          # Always start first partition at 1MB to ensure partitions are aligned with underlying storage stripes
          if [[ $i -eq 1 ]]; then
            p_start=1
          fi
          p_end=$(($p_start + partition_size - 2))
          echo " INFO: Creating partition $i from ${p_start}MB to ${p_end}MB"
          parted -s -a optimal /dev/$data_disk mkpart data ${p_start}Mb ${p_end}Mb
        done

        pause

        # Create filesystems with standard options
        for i in $(seq 1 $NUMBER_OF_PARTITIONS); do
          echo " INFO: Creating XFS filesystem for data$i on /dev/${data_disk}${i}"
          mkfs.xfs $XFS_OPTS -L $LABEL_PREFIX$i /dev/${data_disk}${i}
        done

        echo " INFO: Requesting kernel re-read of partition table on /dev/${data_disk}"
        partprobe /dev/${data_disk}

        echo "   OK: Partitioning completed, have a nice day"
      else
        echo "ERROR: User aborted." 
      fi

    else
      echo "ERROR: Boot disk is larger than data disk, aborting."
      exit 1
    fi

  else
    echo "ERROR: $data_disk_count data disks found"
    echo "$data_disk"
    exit 1
  fi

else
  echo "ERROR: Could not determine boot disk"
  exit 1
fi
