# PV2HVM

## requirement
- must run on EC2 instance
- AWS SDK for Ruby
- EC2 Instance Profile with EC2 admin privilages
- source AMI must be your own AMI (or allowed to create volume of root snapshot])
- source AMI has grub installed
- ~~source root volume must not be partitioned (root_device_name must be /dev/sda1 or /dev/xvda1)~~

## limitation
- only tested with recent Amazon Linux AMI

## usage
```
[root@ip-10-187-27-115 ~]# /var/tmp/pv2hvm.rb ami-1852a870
source ami=ami-1852a870
-- prepare volume
creating target volume with size : 3
 vol-6d215124 created and attached to /dev/sdo
creating source volume from snapshot : snap-451faeec
 vol-aa2050e3 created and attached to /dev/sdm

-- copy partition
# parted /dev/xvdo --script 'mklabel msdos mkpart primary 1M -1s print quit'
Model: Xen Virtual Block Device (xvd)
Disk /dev/xvdo: 3221MB
Sector size (logical/physical): 512B/512B
Partition Table: msdos

Number  Start   End     Size    Type     File system  Flags
 1      1049kB  3221MB  3220MB  primary


# partprobe /dev/xvdo

# udevadm settle

# dd if=/dev/xvdm of=/dev/xvdo1
4194304+0 records in
4194304+0 records out
2147483648 bytes (2.1 GB) copied, 248.027 s, 8.7 MB/s

-- install grub
# mount /dev/xvdo1 /mnt

# cp -a /dev/xvdo /dev/xvdo1 /mnt/dev/

# rm -f /mnt/boot/grub/*stage*

# cp /mnt/usr/*/grub/*/*stage* /mnt/boot/grub/

# rm -f /mnt/boot/grub/device.map

# printf "device (hd0) /dev/xvdo\nroot (hd0,0)\nsetup (hd0)\n" | chroot /mnt grub --batch
Probing devices to guess BIOS drives. This may take a long time.


    GNU GRUB  version 0.97  (640K lower / 3072K upper memory)

 [ Minimal BASH-like line editing is supported.  For the first word, TAB
   lists possible command completions.  Anywhere else TAB lists the possible
   completions of a device/filename.]
grub> device (hd0) /dev/xvdo
grub> root (hd0,0)
 Filesystem type is ext2fs, partition type 0x83
grub> setup (hd0)
 Checking if "/boot/grub/stage1" exists... yes
 Checking if "/boot/grub/stage2" exists... yes
 Checking if "/boot/grub/e2fs_stage1_5" exists... yes
 Running "embed /boot/grub/e2fs_stage1_5 (hd0)"...  31 sectors are embedded.
succeeded
 Running "install /boot/grub/stage1 (hd0) (hd0)1+31 p (hd0,0)/boot/grub/stage2 /boot/grub/grub.conf"... succeeded
Done.
grub>
# cp /mnt/boot/grub/menu.lst /mnt/boot/grub/menu.lst.bak

# cat /mnt/boot/grub/menu.lst.bak | perl -pe "s/\(hd0\)/\(hd0,0\)/;s/console=\S+/console=ttyS0/;s/root=\S+/root=LABEL=\//" > /mnt/boot/grub/menu.lst

# rm -f /mnt/dev/xvdo /mnt/dev/xvdo1

# umount /mnt

-- create snapshot of target volume
snapshot ID = snap-43cbceea
image Id = ami-983afef0
-- cleanup
deleting volumes
 vol-aa2050e3 deleted
 vol-6d215124 deleted

```
