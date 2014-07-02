#!/usr/bin/env ruby
require 'aws-sdk'
require 'net/http'

class Pv2hvm

  def initialize(ami)
    @ami=ami
    @instanceId=ec2metadata("instance-id")
    @az=ec2metadata("placement/availability-zone")
    @region=@az.sub(/.$/,'')
    puts "source ami="+@ami
    AWS.config(:region => @region)
    @ec2 = AWS::EC2.new()
    @src_ami=@ec2.images[@ami]
    check_ami @src_ami
    @src=@src_ami.block_device_mappings[@src_ami.root_device_name]
  end

  def check_ami(ami)
    abort("virtualization_type must be paravirtual") if ami.virtualization_type != :paravirtual
    abort("root_device_type must be EBS") if ami.root_device_type != :ebs
  end

  def convert
    self.prepare_disk()
    self.copy_disk()
    self.install_grub()
  end

  def prepare_disk
    puts "-- prepare volume"

    if @src_ami.root_device_name.match(/1$/)
      dst_vol_size=@src[:volume_size]+1
    else
      dst_vol_size=@src[:volume_size]
    end

    puts "creating target volume with size : "+dst_vol_size.to_s
    @dst_vol = @ec2.volumes.create(:size => dst_vol_size , :availability_zone => @az, :volume_type => "gp2")
    sleep 1 while @dst_vol.status != :available
    @dst_attachment = @dst_vol.attach_to(@ec2.instances[@instanceId], "/dev/sdo")
    sleep 1 while @dst_attachment.status != :attached
    sleep 1 while !File.blockdev?("/dev/sdo")
    puts " #{@dst_vol.id} created and attached to /dev/sdo"

    puts "creating source volume from snapshot : "+@src[:snapshot_id]
    @src_vol = @ec2.volumes.create(:snapshot_id => @src[:snapshot_id], :availability_zone => @az, :volume_type => "gp2")
    sleep 1 while @src_vol.status != :available
    @src_attachment = @src_vol.attach_to(@ec2.instances[@instanceId], "/dev/sdm")
    sleep 1 while @src_attachment.status != :attached
    sleep 1 while !File.blockdev?("/dev/sdm")
    puts " #{@src_vol.id} created and attached to /dev/sdm"

    puts ""

  end

  def copy_disk
    puts "-- copy disk"
    if @src_ami.root_device_name.match(/1$/)
      commands=[
        "parted /dev/xvdo --script 'mklabel msdos mkpart primary 1M -1s print quit'",
        "partprobe /dev/xvdo",
        "udevadm settle",
        "dd if=/dev/xvdm of=/dev/xvdo1",
      ]
    else
      commands=[
        "dd if=/dev/xvdm of=/dev/xvdo",
        "partprobe /dev/xvdo",
        "udevadm settle",
      ]
    end

    commands.each{|command|
      puts "# #{command}"
      abort("#{command.split(/\s+/)[0]} failed.") if !system(command)
      puts ""
    }
  end

  def install_grub
    puts "-- install grub"
    [
      "mount /dev/xvdo1 /mnt",
      "cp -a /dev/xvdo /dev/xvdo1 /mnt/dev/",
      "rm -f /mnt/boot/grub/*stage*",
      "cp /mnt/usr/*/grub/*/*stage* /mnt/boot/grub/",
      "rm -f /mnt/boot/grub/device.map",
      'printf "device (hd0) /dev/xvdo\nroot (hd0,0)\nsetup (hd0)\n" | chroot /mnt grub --batch',
      "cat /mnt/boot/grub/menu.lst | tee /dev/stderr > /mnt/boot/grub/menu.lst.bak",
      'cat /mnt/boot/grub/menu.lst.bak | perl -pe "s/\(hd0\)/\(hd0,0\)/;s/console=\S+/console=ttyS0/" | tee /dev/stderr > /mnt/boot/grub/menu.lst',
      "rm -f /mnt/dev/xvdo /mnt/dev/xvdo1",
      "umount /mnt",
    ].each{|command|
      puts "# #{command}"
      abort("#{command.split(/\s+/)[0]} failed.") if !system(command)
      puts ""
    }
  end

  def register
    puts "-- create snapshot of target volume"
    @snapshot=@dst_vol.create_snapshot(description = "pv2hvm source AMI = "+@ami)
    puts "snapshot ID = #{@snapshot.id}"
    sleep 1 while @snapshot.status != :completed
    @dst_ami=@ec2.images.create(
      :root_device_name=>'/dev/xvda',
      :block_device_mappings=>{"/dev/xvda" => {:snapshot => @snapshot, :volume_type => 'gp2'}},
      :virtualization_type => "hvm",
      :name => @src_ami.name + "(HVM)")
    puts "image Id = #{@dst_ami.id}"
  end

  def cleanup
    puts "-- cleanup"
    self.delete_volumes()
  end

  def delete_volumes
    puts "deleting volumes"
    [@src_vol,@dst_vol].each{ |vol|
      vol.attachments.each{ |attachment|
        attachment.delete(:force => true)
      }
      sleep 1 until vol.status == :available
      vol.delete
      puts " #{vol.id} deleted"
    }
  end

  def ec2metadata(path)
    Net::HTTP.get '169.254.169.254', '/latest/meta-data/'+path
  end

end

if (ARGV.length==0)
  puts "usage: pv2hvm.rb ami-12345678 [ ami-01234567 ...]"
else
  ARGV.each{|ami|
    pv2hvm=Pv2hvm.new(ami)
    pv2hvm.convert
    pv2hvm.register
    pv2hvm.cleanup
  }
end
