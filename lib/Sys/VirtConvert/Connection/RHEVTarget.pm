# Sys::VirtConvert::Connection::RHEVTarget
# Copyright (C) 2010-2012 Red Hat Inc.
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

use strict;
use warnings;

package rhev_util;

sub get_uuid
{
    my $uuidgen;
    open($uuidgen, '-|', 'uuidgen') or die("Unable to execute uuidgen: $!");

    my $uuid;
    while(<$uuidgen>) {
        chomp;
        $uuid = $_;
    }
    close($uuidgen) or die("uuidgen returned an error");

    return $uuid;
}


package Sys::VirtConvert::Connection::RHEVTarget::WriteStream;

use File::Spec::Functions qw(splitpath);
use POSIX;

use Sys::VirtConvert::ExecHelper;
use Sys::VirtConvert::Util qw(:DEFAULT rhev_helper);

use Locale::TextDomain 'virt-v2v';

our @streams;

sub new
{
    my $class = shift;
    my ($volume, $convert) = @_;

    my $self = {};
    bless($self, $class);

    # Store a reference to ourself
    push(@streams, $self);

    $self->{written} = 0;
    $self->{volume} = $volume;
    rhev_helper(sub {
        my $path = $volume->get_path();
        my $format = $volume->get_format();

        # Create the output directory
        my (undef, $dir, undef) = splitpath($path);
        mkdir($dir) or v2vdie __x('Failed to create directory {dir}: {error}',
                                  dir => $dir, error => $!);

        # Create the new volume with qemu-img
        # Note that this will always create a sparse volume. We make it
        # non-sparse if required by explicitly writing zeroes to it while
        # copying.
        my @qemuimg = ('qemu-img', 'create', '-f', $format,
                                             $path, $volume->get_size());

        my $eh = Sys::VirtConvert::ExecHelper->run(@qemuimg);
        v2vdie __x('Failed to create new volume {path} '.
                   'with format {format}. Error was: {error}',
                   path => $path,
                   format => $format,
                   error => $eh->output()) if $eh->status() != 0;

        my $transfer = new Sys::VirtConvert::Transfer::Local
            ($path, 0, $format, $volume->is_sparse());
        $self->{writer} = $transfer->get_write_stream($convert);
    });

    return $self;
}

sub _write_metadata
{
    my $self = shift;

    my $volume = $self->{volume};
    my $path = $volume->get_path().'.meta';

    my $meta;
    rhev_helper(sub {
        # Write out the .meta file
        open($meta, '>', $path)
            or v2vdie __x('Unable to open {path} for writing: {error}',
                          path => $path, error => $!);
    });

    print $meta "DOMAIN=".$volume->_get_domainuuid()."\n";
    print $meta "VOLTYPE=LEAF\n";
    print $meta "CTIME=".$volume->_get_creation()."\n";
    print $meta "FORMAT=".$volume->_get_rhev_format()."\n";
    print $meta "IMAGE=".$volume->_get_imageuuid()."\n";
    print $meta "DISKTYPE=1\n";
    print $meta "PUUID=00000000-0000-0000-0000-000000000000\n";
    print $meta "LEGALITY=LEGAL\n";
    print $meta "MTIME=".$volume->_get_creation()."\n";
    print $meta "POOL_UUID=00000000-0000-0000-0000-000000000000\n";
    print $meta "SIZE=".($volume->get_size() / 512)."\n";
    print $meta "TYPE=".uc($volume->_get_rhev_type())."\n";
    print $meta "DESCRIPTION=Exported by virt-v2v\n";
    print $meta "EOF\n";

    close($meta)
        or v2vdie __x('Error closing {path}: {error}',
                      path => $path, error => $!);
}

sub write
{
    my $self = shift;
    my ($buf) = @_;

    $self->{writer}->write($buf);
    $self->{written} += length($buf);
}

sub close
{
    my $self = shift;

    # Nothing to do if we've already closed the writer
    my $writer = $self->{writer};
    return unless (defined($writer));
    delete($self->{writer});

    # Pad the file up to a 512 byte boundary
    my $pad = (512 - ($self->{written} % 512)) % 512;
    $writer->write("\0" x $pad) if ($pad);

    $writer->close();

    # Update the volume's disk usage
    my $volume = $self->{volume};
    $volume->{usage} = $writer->get_usage();

    $self->_write_metadata();
}

# Immediately close all open WriteStreams
sub _cleanup
{
    my $stream;
    while ($stream = shift(@streams)) {
        eval {
            delete($stream->{writer});
        };
        warn($@) if ($@);
    }
}

sub DESTROY
{
    my $self = shift;

    my $err = $?;

    $self->close();

    $? |= $err;

    # Remove the global reference
    @streams = grep { defined($_) && $_ != $self } @streams;
}


package Sys::VirtConvert::Connection::RHEVTarget::Transfer;

use Sys::VirtConvert::Util;

use Carp;
use Locale::TextDomain 'virt-v2v';

sub new
{
    my $class = shift;
    my ($volume) = @_;

    my $self = {};
    bless($self, $class);

    $self->{volume} = $volume;

    return $self;
}

sub local_path
{
    return shift->{volume}->get_path();
}

sub get_read_stream
{
    v2vdie __('Unable to read data from RHEV.');
}

sub get_write_stream
{
    my $self = shift;
    my ($convert) = @_;

    my $volume = $self->{volume};
    return new Sys::VirtConvert::Connection::RHEVTarget::WriteStream($volume,
                                                                     $convert);
}

sub DESTROY
{
    # Remove circular reference
    delete(shift->{volume});
}


package Sys::VirtConvert::Connection::RHEVTarget::Vol;

use File::Spec::Functions;
use File::Temp qw(tempdir);
use POSIX;

use Sys::VirtConvert::Util qw(:DEFAULT rhev_helper);
use Locale::TextDomain 'virt-v2v';

our %vols_by_path;
our @vols;
our $tmpdir;

@Sys::VirtConvert::Connection::RHEVTarget::Vol::ISA =
    qw(Sys::VirtConvert::Connection::Volume);

sub new
{
    my $class = shift;
    my ($mountdir, $domainuuid, $format, $insize, $sparse) = @_;

    my $root = catdir($mountdir, $domainuuid);

    # Initialise the package-wide temp directory if required
    rhev_helper(sub {
        $tmpdir = tempdir("v2v.XXXXXXXX", DIR => $root);
    }) unless (defined($tmpdir));

    my $imageuuid = rhev_util::get_uuid();
    my $voluuid   = rhev_util::get_uuid();

    my $imagedir    = catdir($root, 'images', $imageuuid);
    my $imagetmpdir = catdir($tmpdir, $imageuuid);
    my $volpath     = catfile($imagetmpdir, $voluuid);

    # RHEV needs disks to be a multiple of 512 in size. We'll pad up to this
    # size if necessary.
    my $outsize = ceil($insize/512) * 512;

    my $creation = time();

    my $self = $class->SUPER::new($imageuuid, $format, $volpath, $outsize,
                                  undef, $sparse, 0);
    $self->{transfer} =
        new Sys::VirtConvert::Connection::RHEVTarget::Transfer($self);

    $self->{imageuuid}  = $imageuuid;
    $self->{voluuid}    = $voluuid;
    $self->{domainuuid} = $domainuuid;

    $self->{imagedir}    = $imagedir;
    $self->{imagetmpdir} = $imagetmpdir;

    $self->{creation} = $creation;

    # Convert format into something RHEV understands
    my $rhev_format;
    if ($format eq 'raw') {
        $self->{rhev_format} = 'RAW';
    } elsif ($format eq 'qcow2') {
        $self->{rhev_format} = 'COW';
    } else {
        v2vdie __x('RHEV cannot handle volumes of format {format}',
                   format => $format);
    }

    # Generate the RHEV type
    # N.B. This must be in mixed case in the OVF, but in upper case in the .meta
    # file. We store it in mixed case and convert to upper when required.
    $self->{rhev_type} = $sparse ? 'Sparse' : 'Preallocated';

    $vols_by_path{$volpath} = $self;
    push(@vols, $self);

    return $self;
}

sub _get_by_path
{
    my $class = shift;
    my ($path) = @_;

    return $vols_by_path{$path};
}

sub _get_domainuuid
{
    return shift->{domainuuid};
}

sub _get_imageuuid
{
    return shift->{imageuuid};
}

sub _get_voluuid
{
    return shift->{voluuid};
}

sub _get_creation
{
    return shift->{creation};
}

sub _get_rhev_format
{
    return shift->{rhev_format};
}

sub _get_rhev_type
{
    return shift->{rhev_type};
}

# Must be called in rhev_helper context
sub _move_vols
{
    my $class = shift;

    foreach my $vol (@vols) {
        rename($vol->{imagetmpdir}, $vol->{imagedir})
            or v2vdie __x('Unable to move volume from temporary '.
                          'location {tmpdir} to {dir}',
                          tmpdir => $vol->{imagetmpdir},
                          dir => $vol->{imagedir});
    }

    $class->_cleanup();
}

# Must be called in rhev_helper context
sub _cleanup
{
    my $class = shift;

    return unless (defined($tmpdir));

    my $ret = system('rm', '-rf', $tmpdir);
    if (WEXITSTATUS($ret) != 0) {
        logmsg WARN, __x('Error whilst attempting to remove temporary '.
                         'directory {dir}', dir => $tmpdir);
    }
    $tmpdir = undef;
}

package Sys::VirtConvert::Connection::RHEVTarget;

use File::Temp qw(tempdir);
use File::Spec::Functions;
use POSIX;
use Time::gmtime;

use Sys::VirtConvert::ExecHelper;
use Sys::VirtConvert::Util qw(:DEFAULT rhev_helper rhev_ids);

use Locale::TextDomain 'virt-v2v';

=head1 NAME

Sys::VirtConvert::Connection::RHEVTarget - Output to a RHEV Export storage
domain

=head1 METHODS

=over

=item Sys::VirtConvert::Connection::RHEVTarget->new(domain_path)

Create a new Sys::VirtConvert::Connection::RHEVTarget object.

=over

=item domain_path

The NFS path to an initialised RHEV Export storage domain.

=back

=cut

sub new
{
    my $class = shift;
    my ($domain_path) = @_;

    # Must do this before bless, or DESTROY will be called
    v2vdie __('You must be root to output to RHEV') unless $> == 0;

    my $mountdir = tempdir();

    my ($_uid, $_gid) = rhev_ids();

    # Needs to be read by vdsm:kvm
    chown($_uid, $_gid, $mountdir)
        or v2vdie __x('Unable to change ownership of {mountdir} to vdsm:kvm',
                      mountdir => $mountdir);

    my $self = {};
    bless($self, $class);

    $self->{mountdir} = $mountdir;
    $self->{domain_path} = $domain_path;

    my $eh = Sys::VirtConvert::ExecHelper->run('mount',
                                               $domain_path, $mountdir);
    v2vdie __x('Failed to mount {path}. Command exited with '.
               'status {status}. Output was: {output}',
               path => $domain_path,
               status => $eh->status(),
               output => $eh->output()) if $eh->status() != 0;

    my $dir;
    rhev_helper(sub {
        opendir($dir, $mountdir)
            or v2vdie __x('Unable to open {mountdir}: {error}',
                          mountdir => $mountdir, error => $!);
    });

    my @entries;
    foreach my $entry (readdir($dir)) {
        # return entries which look like uuids
        push(@entries, $entry)
            if ($entry =~ /^[0-9a-z]{8}-(?:[0-9a-z]{4}-){3}[0-9a-z]{12}$/);
    }

    v2vdie __x('{domain_path} contains multiple possible '.
               'domains. It may only contain one.',
               domain_path => $domain_path) if @entries > 1;

    my ($domainuuid) = @entries;
    v2vdie __x('{domain_path} does not contain an initialised storage domain.',
               domain_path => $domain_path) unless defined($domainuuid);
    $self->{domainuuid} = $domainuuid;

    # Check that the domain has been attached to a Data Center by checking that
    # the master/vms directory exists
    my $vms_rel = catdir($domainuuid, 'master', 'vms');
    my $vms_abs = catdir($mountdir, $vms_rel);
    my $attached;
    rhev_helper(sub {
        $attached = -d $vms_abs ? 1 : 0;
    });
    v2vdie __x('{domain_path} has not been attached to a RHEV '.
               'data center ({path} does not exist).',
               domain_path => $domain_path, path => $vms_rel) unless $attached;

    return $self;
}

sub DESTROY
{
    my $self = shift;

    # The ExecHelper we use to unmount the export directory will overwrite $?
    # when the helper process exits. We need to preserve it for our own exit
    # status.
    my $retval = $?;

    eval {
        # Ensure there are no remaining writer processes
        Sys::VirtConvert::Connection::RHEVTarget::WriteStream->_cleanup();

        rhev_helper(sub {
            # Cleanup the volume temporary directory
            Sys::VirtConvert::Connection::RHEVTarget::Vol->_cleanup();
        });
    };
    if ($@) {
        warn($@);
        $retval |= 1;
    }

    my $eh = Sys::VirtConvert::ExecHelper->run('umount', $self->{mountdir});
    if ($eh->status() != 0) {
        logmsg WARN, __x('Failed to unmount {path}. Command exited with '.
                         'status {status}. Output was: {output}',
                         path => $self->{domain_path},
                         status => $eh->status(),
                         output => $eh->output());
        # Exit with an error if the child failed.
        $retval |= $eh->status();
    }

    unless (rmdir($self->{mountdir})) {
        logmsg WARN, __x('Failed to remove mount directory {dir}: {error}',
                         dir => $self->{mountdir}, error => $!);
        $retval |= 1;
    }

    $? |= $retval;
}

=item create_volume(name, format, size, is_sparse)

Create a new volume in the export storage domain

=over

=item name

The name of the volume which is being created.

=item format

The file format of the target volume, as returned by qemu.

=item size

The size of the volume which is being created in bytes.

=item is_sparse

1 if the target volume is sparse, 0 otherwise.

=back

create_volume() returns a Sys::VirtConvert::Connection::RHEVTarget::Vol object.

=cut

sub create_volume
{
    my $self = shift;
    my ($name, $format, $size, $is_sparse) = @_;

    return Sys::VirtConvert::Connection::RHEVTarget::Vol->new
        ($self->{mountdir}, $self->{domainuuid}, $format, $size, $is_sparse);
}

=item volume_exists(name)

Check if volume I<name> exists in the target storage domain.

Always returns 0, as RHEV storage domains don't have names

=cut

sub volume_exists
{
    return 0;
}

=item get_volume(name)

Not defined for RHEV output

=cut

sub get_volume
{
    my $self = shift;
    my ($name) = @_;

    die("Cannot retrieve an existing RHEV storage volume by name");
}

=item guest_exists(name)

This always returns 0 for a RHEV target.

=cut

sub guest_exists
{
    return 0;
}

=item create_guest(g, root, meta, config, guestcaps, output_name)

Create the guest in the target

=cut

sub create_guest
{
    my $self = shift;
    my ($g, $root, $meta, $config, $guestcaps, $output_name) = @_;

    # Get the number of virtual cpus
    my $ncpus = $meta->{cpus};

    # Get the amount of memory in MB
    my $memsize = ceil($meta->{memory}/1024/1024);

    # Generate a creation date
    my $vmcreation = _format_time(gmtime());

    my $vmuuid = rhev_util::get_uuid();

    my $ostype = _get_os_type($g, $root);
    my $vmtype = _get_vm_type($g, $root, $meta);

    my $ovf = new XML::DOM::Parser->parse(<<EOF);
<ovf:Envelope
    xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData"
    xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1/"
    ovf:version="0.9">

    <References/>

    <Section xsi:type="ovf:NetworkSection_Type">
        <Info>List of networks</Info>
    </Section>

    <Section xsi:type="ovf:DiskSection_Type">
        <Info>List of Virtual Disks</Info>
    </Section>

    <Content ovf:id="out" xsi:type="ovf:VirtualSystem_Type">
        <Name>$output_name</Name>
        <TemplateId>00000000-0000-0000-0000-000000000000</TemplateId>
        <TemplateName>Blank</TemplateName>
        <Description>Imported with virt-v2v</Description>
        <Domain/>
        <CreationDate>$vmcreation</CreationDate>
        <IsInitilized>True</IsInitilized>
        <IsAutoSuspend>False</IsAutoSuspend>
        <TimeZone/>
        <IsStateless>False</IsStateless>
        <Origin>0</Origin>
        <VmType>$vmtype</VmType>
        <DefaultDisplayType>0</DefaultDisplayType>

        <Section ovf:id="$vmuuid" ovf:required="false" xsi:type="ovf:OperatingSystemSection_Type">
          <Info>Guest Operating System</Info>
          <Description>$ostype</Description>
        </Section>

        <Section xsi:type="ovf:VirtualHardwareSection_Type">
            <Info>$ncpus CPU, $memsize Memory</Info>
            <Item>
                <rasd:Caption>$ncpus virtual cpu</rasd:Caption>
                <rasd:Description>Number of virtual CPU</rasd:Description>
                <rasd:InstanceId>1</rasd:InstanceId>
                <rasd:ResourceType>3</rasd:ResourceType>
                <rasd:num_of_sockets>$ncpus</rasd:num_of_sockets>
                <rasd:cpu_per_socket>1</rasd:cpu_per_socket>
            </Item>
            <Item>
                <rasd:Caption>$memsize MB of memory</rasd:Caption>
                <rasd:Description>Memory Size</rasd:Description>
                <rasd:InstanceId>2</rasd:InstanceId>
                <rasd:ResourceType>4</rasd:ResourceType>
                <rasd:AllocationUnits>MegaBytes</rasd:AllocationUnits>
                <rasd:VirtualQuantity>$memsize</rasd:VirtualQuantity>
            </Item>
            <Item>
                <rasd:Caption>USB Controller</rasd:Caption>
                <rasd:InstanceId>4</rasd:InstanceId>
                <rasd:ResourceType>23</rasd:ResourceType>
                <rasd:UsbPolicy>Disabled</rasd:UsbPolicy>
            </Item>
            <Item>
                <rasd:Caption>Graphical Controller</rasd:Caption>
                <rasd:InstanceId>5</rasd:InstanceId>
                <rasd:ResourceType>20</rasd:ResourceType>
                <rasd:VirtualQuantity>1</rasd:VirtualQuantity>
            </Item>
        </Section>
    </Content>
</ovf:Envelope>
EOF

    logmsg WARN, __('This guest requires a password for connection to its '.
                    'display, but this is not supported by RHEV. The '.
                    'converted guest\'s display will not require a separate '.
                    'password to connect.')
        if exists($meta->{display}) && exists($meta->{display}->{password});

    $self->_disks($ovf, $meta, $guestcaps);
    $self->_networks($ovf, $meta, $config, $guestcaps);

    my $mountdir = $self->{mountdir};
    my $domainuuid = $self->{domainuuid};

    my $dir = catdir($mountdir, $domainuuid, 'master', 'vms', $vmuuid);
    rhev_helper(sub {
        mkdir($dir)
            or v2vdie __x('Failed to create directory {dir}: {error}',
                          dir => $dir, error => $!);

        Sys::VirtConvert::Connection::RHEVTarget::Vol->_move_vols();

        my $vm;
        my $ovfpath = catfile($dir, $vmuuid.'.ovf');
        open($vm, '>', $ovfpath)
            or v2vdie __x('Unable to open {path} for writing: {error}',
                          path => $ovfpath, error => $!);

        print $vm $ovf->toString();
        close($vm);
    });
}

# Work out how to describe the guest OS to RHEV. Possible values are:
#  Other
#   Not used
#
#  RHEL3
#  RHEL3x64
#   os = linux
#   distro = rhel
#   major_version = 3
#
#  RHEL4
#  RHEL4x64
#   os = linux
#   distro = rhel
#   major_version = 4
#
#  RHEL5
#  RHEL5x64
#   os = linux
#   distro = rhel
#   major_version = 5
#
#  OtherLinux
#   os = linux
#
#  WindowsXP
#   os = windows
#   major_version = 5
#   minor_version = 1
#
#  WindowsXP
#   os = windows
#   major_version = 5
#   minor_version = 2
#   product_name = 'Microsoft Windows XP'
#
#  Windows2003
#  Windows2003x64
#   os = windows
#   major_version = 5
#   minor_version = 2
#   N.B. This also matches Windows 2003 R2, which there's no option for
#
#  Windows2008
#  Windows2008x64
#   os = windows
#   major_version = 6
#   minor_version = 0
#   N.B. This also matches Vista, which there's no option for
#
#  Windows7
#  Windows7x64
#   os = windows
#   major_version = 6
#   minor_version = 1
#   product_variant = 'Client'
#
#  Windows2008R2x64
#   os = windows
#   major_version = 6
#   minor_version = 1
#   product_variant != 'Client'
#
#  Unassigned
#   None of the above
#
# N.B. We deliberately fall through to Unassigned rather than Other, because
# this represents a failure to match. We don't want to assert that the OS is not
# one of the above values in case we're wrong.
sub _get_os_type
{
    my ($g, $root) = @_;

    my $arch = $g->inspect_get_arch($root);

    my $arch_suffix = '';
    if ($arch eq 'x86_64') {
        $arch_suffix = 'x64';
    } elsif ($arch ne 'i386') {
        logmsg WARN, __x('Unsupported architecture: {arch}', arch => $arch);
        return undef;
    }

    my $type;

    $type = _get_os_type_linux($g, $root, $arch_suffix)
        if ($g->inspect_get_type($root) eq 'linux');
    $type = _get_os_type_windows($g, $root, $arch_suffix)
        if ($g->inspect_get_type($root) eq 'windows');

    return 'Unassigned' if (!defined($type));
    return $type;
}

sub _get_os_type_windows
{
    my ($g, $root, $arch_suffix) = @_;

    my $major   = $g->inspect_get_major_version($root);
    my $minor   = $g->inspect_get_minor_version($root);
    my $product = $g->inspect_get_product_name($root);

    if ($major == 5) {
        if ($minor == 1 ||
            # Windows XP Pro x64 is identified as version 5.2
            ($minor == 2 && $product =~ /\bXP\b/))
        {
            # RHEV doesn't differentiate Windows XP by architecture
            return "WindowsXP";
        }

        if ($minor == 2) {
            return "Windows2003".$arch_suffix;
        }
    }

    if ($major == 6 && $minor == 0) {
        return "Windows2008".$arch_suffix;
    }

    if ($major == 6 && $minor == 1) {
        # The only 32 bit Windows 6.1 is Windows 7
        return "Windows7" if length($arch_suffix) == 0;

        # This API is new in libguestfs 1.10
        # If it's not present, we can't differentiate between Win7 and Win2k8r2
        # for amd64
        if (defined($g->can('inspect_get_product_variant')) &&
            $g->inspect_get_product_variant($root) eq 'Client')
        {
            return "Windows7".$arch_suffix;
        }

        return "Windows2008R2".$arch_suffix;
    }

    logmsg WARN, __x('Unknown Windows version: {major}.{minor}',
                     major => $major, minor => $minor);
    return undef;
}

sub _get_os_type_linux
{
    my ($g, $root, $arch_suffix) = @_;

    my $distro  = $g->inspect_get_distro($root);
    my $major   = $g->inspect_get_major_version($root);

    # XXX: RHEV 2.2 doesn't support a RHEL 6 target, however RHEV 2.3+ will.
    # For the moment, we set RHEL 6 to be 'OtherLinux', however we will need to
    # distinguish in future between RHEV 2.2 target and RHEV 2.3 target to know
    # what is supported.
    if ($distro eq 'rhel' && $major < 6) {
        return "RHEL".$major.$arch_suffix;
    }

    # Unlike Windows, Linux has its own fall-through option
    return "OtherLinux";
}

use constant DESKTOP => 0;
use constant SERVER => 1;

sub _get_vm_type
{
    my ($g, $root, $meta) = @_;

    # Return whatever we were explicitly passed on the command line
    my $vmtype = $meta->{vmtype};
    return $vmtype eq "desktop" ? DESKTOP : SERVER if (defined($vmtype));

    # Make an informed guess based on the OS type
    return _get_vm_type_linux($g, $root)
        if ($g->inspect_get_type($root) eq 'linux');

    return _get_vm_type_windows($g, $root)
        if ($g->inspect_get_type($root) eq 'windows');

    # Final fall-through is server
    return SERVER;
}

sub _get_vm_type_windows
{
    my ($g, $root) = @_;

    my $major   = $g->inspect_get_major_version($root);
    my $minor   = $g->inspect_get_minor_version($root);
    my $product = $g->inspect_get_product_name($root);

    if ($major == 5) {
        # Windows XP
        if ($minor == 1 ||
            # Windows XP Pro x64 is identified as version 5.2
            ($minor == 2 && $product =~ /\bXP\b/))
        {
            return DESKTOP;
        }

        # Windows 2003
        if ($minor == 2) {
            return SERVER;
        }
    }

    # Windows 2008 & Vista
    if ($major == 6 && $minor == 0) {
        return SERVER if $product =~ /\bServer\b/;
        return DESKTOP;
    }

    # Windows 2008r2 & 7
    if ($major == 6 && $minor == 1) {
        return SERVER if $product =~ /\bServer\b/;
        return DESKTOP;
    }

    return SERVER;
}

sub _get_vm_type_linux
{
    my ($g, $root) = @_;

    my $distro  = $g->inspect_get_distro($root);
    my $major   = $g->inspect_get_major_version($root);
    my $product = $g->inspect_get_product_name($root);

    if ($distro eq 'rhel') {
        if ($major >= 5) {
            # This is accurate for RHEL 5 and RHEL 6. We can only guess about
            # future versions of RHEL, but it's as good a guess as any. We
            # negate this test to ensure we default to SERVER if our guess is
            # wrong.
            return DESKTOP if $product !~ /\bServer\b/;
            return SERVER;
        }

        if ($major == 4 || $major == 3) {
            return SERVER if $product =~ /\b(ES|AS)\b/;
            return DESKTOP;
        }

        return SERVER if $major == 2;
    }

    elsif ($distro eq 'fedora') {
        return DESKTOP;
    }

    return SERVER;
}

sub _format_time
{
    my ($time) = @_;
    return sprintf("%04d/%02d/%02d %02d:%02d:%02d",
                   $time->year() + 1900, $time->mon() + 1, $time->mday(),
                   $time->hour(), $time->min(), $time->sec());
}

sub _disks
{
    my $self = shift;
    my ($ovf, $meta, $guestcaps) = @_;

    my ($references) = $ovf->findnodes('/ovf:Envelope/References');
    die("no references") unless (defined($references));

    my ($disksection) = $ovf->findnodes("/ovf:Envelope/Section".
                                      "[\@xsi:type = 'ovf:DiskSection_Type']");
    die("no disksection") unless (defined($disksection));

    my ($virtualhardware) =
        $ovf->findnodes("/ovf:Envelope/Content/Section".
                        "[\@xsi:type = 'ovf:VirtualHardwareSection_Type'");
    die("no virtualhardware") unless (defined($virtualhardware));

    my $driveno = 1;

    foreach my $disk (@{$meta->{disks}}) {
        my $path = $disk->{dst}->get_path();
        my $vol = Sys::VirtConvert::Connection::RHEVTarget::Vol->_get_by_path
            ($path);

        die('metadata contains path not written by virt-v2v: ', $path)
            unless defined($vol);

        my $fileref = catdir($vol->_get_imageuuid(), $vol->_get_voluuid());
        my $size_gb = ceil($vol->get_size()/1024/1024/1024);
        my $usage_gb = ceil($vol->get_usage()/1024/1024/1024);

        # Add disk to References
        my $file = $ovf->createElement("File");
        $references->appendChild($file);

        $file->setAttribute('ovf:href', $fileref);
        $file->setAttribute('ovf:id', $vol->_get_voluuid());
        $file->setAttribute('ovf:size', $vol->get_size());
        $file->setAttribute('ovf:description', 'imported by virt-v2v');

        # Add disk to DiskSection
        my $diske = $ovf->createElement("Disk");
        $disksection->appendChild($diske);

        $diske->setAttribute('ovf:diskId', $vol->_get_voluuid());
        $diske->setAttribute('ovf:size', $size_gb);
        $diske->setAttribute('ovf:actual_size', $usage_gb);
        $diske->setAttribute('ovf:fileRef', $fileref);
        $diske->setAttribute('ovf:parentRef', '');
        $diske->setAttribute('ovf:vm_snapshot_id', get_uuid());
        $diske->setAttribute('ovf:volume-format', $vol->_get_rhev_format());
        $diske->setAttribute('ovf:volume-type', $vol->_get_rhev_type());
        $diske->setAttribute('ovf:format', 'http://en.wikipedia.org/wiki/Byte');
        # IDE = 0, SCSI = 1, VirtIO = 2
        $diske->setAttribute('ovf:disk-interface',
                             $guestcaps->{block} eq 'virtio' ? 'VirtIO' : 'IDE');
        $diske->setAttribute('ovf:disk-type', 'System'); # RHBZ#744538
        # The libvirt QEMU driver marks the first disk (in document order) as
        # bootable
        $diske->setAttribute('ovf:boot', $driveno == 1 ? 'True' : 'False');

        # Add disk to VirtualHardware
        my $item = $ovf->createElement('Item');
        $virtualhardware->appendChild($item);

        my $e;
        $e = $ovf->createElement('rasd:Caption');
        $e->addText("Drive $driveno"); # This text MUST begin with the string
                                       # 'Drive ' or the file will not parse
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:InstanceId');
        $e->addText($vol->_get_voluuid());
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:ResourceType');
        $e->addText('17');
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:HostResource');
        $e->addText($fileref);
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:Parent');
        $e->addText('00000000-0000-0000-0000-000000000000');
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:Template');
        $e->addText('00000000-0000-0000-0000-000000000000');
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:ApplicationList');
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:StorageId');
        $e->addText($self->{domainuuid});
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:StoragePoolId');
        $e->addText('00000000-0000-0000-0000-000000000000');
        $item->appendChild($e);

        my $voldate = _format_time(gmtime($vol->_get_creation()));

        $e = $ovf->createElement('rasd:CreationDate');
        $e->addText($voldate);
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:LastModified');
        $e->addText($voldate);
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:last_modified_date');
        $e->addText($voldate);
        $item->appendChild($e);

        $driveno++;
    }
}

sub _networks
{
    my $self = shift;
    my ($ovf, $meta, $config, $guestcaps) = @_;

    my ($networksection) = $ovf->findnodes("/ovf:Envelope/Section".
                                    "[\@xsi:type = 'ovf:NetworkSection_Type']");

    my ($virtualhardware) =
        $ovf->findnodes("/ovf:Envelope/Content/Section".
                        "[\@xsi:type = 'ovf:VirtualHardwareSection_Type'");
    die("no virtualhardware") unless (defined($virtualhardware));

    my $i = 0;
    foreach my $if (@{$meta->{nics}}) {
        my $dev = "eth$i"; $i++;

        # Find an appropriate mapped network
        my ($vnet, undef) = $config->map_network($if->{vnet}, $if->{vnet_type});
        $vnet ||= $if->{vnet};

        my $e = $ovf->createElement("Network");
        $e->setAttribute('ovf:name', $vnet);
        $networksection->appendChild($e);

        my $item = $ovf->createElement('Item');
        $virtualhardware->appendChild($item);

        $e = $ovf->createElement('rasd:Caption');
        $e->addText('Ethernet adapter on '.$vnet);
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:InstanceId');
        $e->addText('3');
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:ResourceType');
        $e->addText('10');
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:ResourceSubType');
        if ($guestcaps->{net} eq 'rtl8139') {
            $e->addText('1');
        } elsif ($guestcaps->{net} eq 'e1000') {
            $e->addText('2');
        } elsif ($guestcaps->{net} eq 'virtio') {
            $e->addText('3');
        } else {
            logmsg WARN, __x('Unknown NIC model {driver} for {dev}. '.
                             'NIC will be {default} when imported.',
                             driver => $guestcaps->{net},
                             dev => $dev,
                             default => 'rtl8139');
            $e->addText('1');
        }
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:Connection');
        $e->addText($vnet);
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:Name');
        $e->addText($dev);
        $item->appendChild($e);

        $e = $ovf->createElement('rasd:MACAddress');
        $e->addText($if->{mac});
        $item->appendChild($e);
    }
}

=back

=head1 COPYRIGHT

Copyright (C) 2010-2012 Red Hat Inc.

=head1 LICENSE

Please see the file COPYING for the full license.

=cut

1;
