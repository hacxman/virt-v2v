#!/usr/bin/perl
# virt-v2v
# Copyright (C) 2009 Red Hat Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use warnings;
use strict;

use Pod::Usage;
use Getopt::Long;
use Data::Dumper;
use XML::Writer;
use Config::Tiny;
use Locale::TextDomain 'virt-v2v';

use Sys::Guestfs;
use Sys::Guestfs::Lib qw(open_guest get_partitions resolve_windows_path
  inspect_all_partitions inspect_partition
  inspect_operating_systems mount_operating_system inspect_in_detail);

use Sys::VirtV2V;
use Sys::VirtV2V::MetadataReader;
use Sys::VirtV2V::GuestOS;
use Sys::VirtV2V::HVTarget;

=encoding utf8

=head1 NAME

virt-v2v - Convert a guest to use KVM

=head1 SYNOPSIS

 virt-v2v guest-domain.xml

 virt-v2v -s virt-v2v.conf guest-domain.xml

 virt-v2v --connect qemu:///system guest-domain.xml

=head1 DESCRIPTION

Virt-v2v converts guests from one virtualization hypervisor to
another.  Currently it is limited in what it can convert.  See the
table below.

 -------------------------------+----------------------------
 SOURCE                         | TARGET
 -------------------------------+----------------------------
 Xen domain managed by          |
 libvirt                        |
                                |
 Xen compatibility:             | KVM guest managed by
   - PV or FV kernel            | libvirt                   
   - with or without PV drivers |   - with virtio drivers   
   - RHEL 3.x, 4.x, 5.x         |     if supported by guest 
                                |  
                                |
 -------------------------------+----------------------------
 
=head1 OPTIONS

=over 4

=cut

my $help;

=item B<--help>

Display brief help.

=cut

my $version;

=item B<--version>

Display version number and exit.

=cut

my $uri;

=item B<--connect URI> | B<-c URI>

Connect to libvirt using the given I<URI>. If omitted, then we connect to the
default libvirt hypervisor.

=cut

my $input = "libvirt";

=item B<--input input> | B<-i input>

The specified guest description uses the given I<input format>. The default is
C<libvirt>. Supported options are:

=over

=item I<libvirt>

Guest argument is the name of a libvirt domain.

=item I<libvirtxml>

Guest argument is the path to an XML file describing a libvirt domain.

=back

=cut

my $config_file;

=item B<--config file> | B<-s file>

Load the virt-v2v configuration from I<file>. There is no default.

=back

=cut

GetOptions ("help|?"      => \$help,
            "version"     => \$version,
            "connect|c=s" => \$uri,
            "input|i=s"   => \$input,
            "config|s=s"  => \$config_file
    ) or pod2usage(2);
pod2usage(0) if($help);

if ($version) {
    print "$Sys::VirtV2V::VERSION\n";
    exit(0);
}

pod2usage(__"virt-v2v: no guest argument given") if @ARGV == 0;

# Read the config file if one was given
my $config = {};
if(defined($config_file)) {
    $config = Config::Tiny->read($config_file);

    # Check we were able to read it
    if(!defined($config)) {
        print STDERR Config::Tiny->errstr."\n";
        exit(1);
    }
}

# Get an appropriate MetadataReader
my $mdr = Sys::VirtV2V::MetadataReader->instantiate($input, $config);
if(!defined($mdr)) {
    print STDERR __x("virt-v2v: {input} is not a valid metadata format",
                     input => $input)."\n";
    exit(1);
}

$mdr->handle_arguments(@ARGV);

# Check MetadataReader is properly initialised
exit 1 unless($mdr->is_configured());

# Configure GuestOS ([files] and [deps] sections)
Sys::VirtV2V::GuestOS->configure($config);

# Connect to libvirt
my @vmm_params = (auth => 1);
push(@vmm_params, uri => $uri) if(defined($uri));
my $vmm = Sys::Virt->new(@vmm_params);

###############################################################################
## Start of processing

# Get a libvirt configuration for the guest
my $dom = $mdr->get_dom($vmm);
exit(1) if(!defined($dom));

# Get a list of the guest's storage devices
my @devices = get_guest_devices($dom);

# Open a libguestfs handle on the guest's devices
my $g = get_guestfs_handle(@devices);

# Inspect the guest
my $os = inspect_guest($g);

# Instantiate a GuestOS instance to manipulate the guest
my $guestos = Sys::VirtV2V::GuestOS->instantiate($g, $os);

# Modify the guest and its metadata for the target hypervisor
Sys::VirtV2V::HVTarget->configure($vmm, $guestos, $dom, $os);

$g->umount_all();
$g->sync();

$vmm->define_domain($dom->toString());


###############################################################################
## Helper functions

sub get_guestfs_handle
{
    my @params = \@_; # Initialise parameters with list of devices

    my $g = open_guest(@params, rw => 1);

    # Mount the transfer iso if GuestOS needs it
    my $transferiso = Sys::VirtV2V::GuestOS->get_transfer_iso();
    $g->add_cdrom($transferiso) if(defined($transferiso));

    # Enable selinux in the guest
    $g->set_selinux(1);

    $g->launch ();
    $g->wait_ready ();

    return $g;
}

# Inspect the guest's storage. Returns an OS hashref as returned by
# inspect_in_detail.
sub inspect_guest
{
    my $g = shift;

    my $use_windows_registry;

    # List of possible filesystems.
    my @partitions = get_partitions ($g);

    # Now query each one to build up a picture of what's in it.
    my %fses =
        inspect_all_partitions ($g, \@partitions,
                                use_windows_registry => $use_windows_registry);

    #print "fses -----------\n";
    #print Dumper(\%fses);

    my $oses = inspect_operating_systems ($g, \%fses);

    #print "oses -----------\n";
    #print Dumper($oses);

    # Only work on single-root operating systems.
    my $root_dev;
    my @roots = keys %$oses;
    die __"no root device found in this operating system image" if @roots == 0;
    die __"multiboot operating systems are not supported by v2v" if @roots > 1;
    $root_dev = $roots[0];

    # Mount up the disks and check for applications.

    my $os = $oses->{$root_dev};
    mount_operating_system ($g, $os, 0);
    inspect_in_detail ($g, $os);

    return $os;
}

sub get_guest_devices
{
    my $dom = shift;

    my @devices;
    foreach my $source ($dom->findnodes('/domain/devices/disk/source')) {
        my $attrs = $source->getAttributes();

        # Get either dev or file, whichever is defined
        my $attr = $attrs->getNamedItem("dev");
        $attr = $attrs->getNamedItem("file") if(!defined($attr));

        defined($attr) or die("source element has neither dev nor file: ".
                              $source.toString());

        push(@devices, $attr->getValue());
    }

    return @devices;
}

=head1 PREPARING TO RUN VIRT-V2V

=head2 Backup the guest

Virt-v2v converts guests 'in-place': it will make changes to a guest directly
without creating a backup. It is recommended that virt-v2v be run against a
copy.

The L<virt-snapshot(1)> tool can be used to convert a guest to use a snapshot
for storage prior to running virt-v2v against it. This snapshot can then be
committed to the original storage after the conversion is confirmed as
successful.

The L<virt-clone(1)> tool can make a complete copy of a guest, including all its
storage.

=head2 Obtain domain XML for the guest domain

Virt-v2v uses a libvirt domain description to determine the current
configuration of the guest, including the location of its storage. This should
be obtained from the host running the guest pre-conversion by running:

 virsh dumpxml <domain> > <domain>.xml

=head1 CONVERTING A GUEST

In the simplest case, virt-v2v can be run as follows:

 virt-v2v <domain>.xml

where C<< <domain>.xml >> is the path to the exported guest domain's xml. This
is the simplest form of conversion. It can only be used when the guest has an
installed kernel which will boot on KVM, i.e. a guest with only paravirtualised
Xen kernels installed will not work. Virtio will be configured if it is
supported, otherwise the guest will be configured to use non-virtio drivers. See
L</GUEST DRIVERS> for details of which drivers will be used.

Virt-v2v can also be configured to install new software into a guest. This might
be necessary if the guest will not boot on KVM without modification, or if you
want to upgrade it to support virtio during conversion. Doing this requires
specifying a configuration file describing where to find the new software. In
this case, virt-v2v is called as:

 virt-v2v -s <virt-v2v.conf> <domain>.xml

See L<virt-v2v.conf(5)> for details of this configuration file. During the
conversion process, if virt-v2v does not detect that the guest is capable of
supporting virtio it will try to upgrade components to resolve this.  On Linux
guests this will involve upgrading the kernel, and may involve upgrading
dependent parts of userspace.

To text boot the new guest in KVM, run:

 virsh start <domain>
 virt-viewer <domain>

If you have created a guest snapshot using L<virt-snapshot(1)>, it can be
committed or rolled back at this stage.

=head1 GUEST CONFIGURATION CHANGES

As well as configuring libvirt appropriately, virt-v2v will make certain changes
to a guest to enable it support running under a KVM host either with or without
virtio driver. These changes are guest OS specific. Currently only Red Hat based
Linux distributions are supported.

=head2 Linux

virt-v2v will make the following changes to a Linux guest:

=over

=item Kernel

Un-bootable, i.e. xen paravirtualised, kernels will be uninstalled. No new
kernel will be installed if there is a remaining kernel which supports virtio.
If no remaining kernel supports virtio and the configuration file specifies a
new kernel it will be installed and configured as the default.

=item X reconfiguration

If the guest has X configured, its display driver will be updated. See L</GUEST
DRIVERS> for which driver will be used.

=item Rename block devices

If changes have caused block devices to change name, these changes will be
reflected in /etc/fstab.

=item Configure device drivers

Whether virtio or non-virtio drivers are configured, virt-v2v will ensure that
the correct network and block drivers are specified in the modprobe
configuration.

=item initrd

virt-v2v will ensure that the initrd for the default kernel supports booting the
root device, whether it is using virtio or not.

=back

=head1 GUEST DRIVERS

Virt-v2v will install the following drivers in a Linux guest:

=head2 VirtIO

 X display      cirrus
 Block          virtio_blk
 Network        virtio_net

Additionally, initrd will preload the virtio_pci driver.

=head2 Non-VirtIO

 X display      cirrus
 Block          sym53c8xx (scsi)
 Network        e1000

=head1 SEE ALSO

L<virt-snapshot(1)>
L<http://libguestfs.org/>.

For Windows registry parsing we require the C<reged> program
from L<http://home.eunet.no/~pnordahl/ntpasswd/>.

=head1 AUTHOR

Richard W.M. Jones L<http://et.redhat.com/~rjones/>

Matthew Booth L<mbooth@redhat.com>

=head1 COPYRIGHT

Copyright (C) 2009 Red Hat Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.