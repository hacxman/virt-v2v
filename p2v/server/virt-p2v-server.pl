#!/usr/bin/perl
# virt-p2v-server
# Copyright (C) 2011 Red Hat Inc.
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
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use warnings;
use strict;

# The YAML module doesn't support YAML generated by Ruby. YAML::Tiny and
# YAML::Syck are both fine. We can't use YAML::Any here because that breaks by
# default.
use YAML::Tiny;

use Locale::TextDomain 'virt-v2v';

use Sys::Guestfs;

use Sys::VirtConvert;
use Sys::VirtConvert::Config;
use Sys::VirtConvert::Converter;
use Sys::VirtConvert::Connection::LibVirtTarget;
use Sys::VirtConvert::Connection::RHEVTarget;
use Sys::VirtConvert::GuestfsHandle;
use Sys::VirtConvert::Util qw(:DEFAULT logmsg_init logmsg_level);

=encoding utf8

=head1 NAME

virt-p2v-server - Receive data from virt-p2v

=head1 DESCRIPTION

virt-p2v-server is invoked over SSH by virt-p2v. It is not intended to be run
manually.

=cut

# SIGPIPE will cause an untidy exit of the perl process, without calling
# destructors. We don't rely on it anywhere, as we check for errors when reading
# from or writing to a pipe.
$SIG{'PIPE'} = 'IGNORE';

# The protocol version we support
use constant VERSION => 0;

# Message types
use constant MSG_VERSION        => 'VERSION';
use constant MSG_LANG           => 'LANG';
use constant MSG_METADATA       => 'METADATA';
use constant MSG_PATH           => 'PATH';
use constant MSG_CONVERT        => 'CONVERT';
use constant MSG_LIST_PROFILES  => 'LIST_PROFILES';
use constant MSG_SET_PROFILE    => 'SET_PROFILE';
use constant MSG_CONTAINER      => 'CONTAINER';
use constant MSG_DATA           => 'DATA';

# Container types
use constant CONT_RAW => 'RAW';

# Global state
my $config;
my $meta;
my $target;

# Initialize logging
logmsg_init('syslog');
#logmsg_level(DEBUG);

# Uncomment these 2 lines to capture debug information from the conversion
# process
#$ENV{'LIBGUESTFS_DEBUG'} = 1;
#$ENV{'LIBGUESTFS_TRACE'} = 1;

logmsg NOTICE, __x("{program} started.", program => 'p2v-server');

# Create a temporary log file to capture output to stderr
my $stderr;
my $stderr_filename = '/var/log/virt-p2v-server.'.time().'.log';

if(!open($stderr, '>', $stderr_filename)) {
    $stderr = undef;
    v2vdie __x("Unable to open log file {file}: {error}",
               file => $stderr_filename, error => $!);
}
open(*STDERR, ">&", $stderr) or v2vdie "dup failed: $!";

# Wrap everything in a big eval to catch any die(). N.B. $SIG{__DIE__} is no
# good for this, as it catches every die(), even those inside an eval
eval {
    # Set the umask to a reasonable default
    umask(0022);

    # We have seen instances where failures in library functions have occurred
    # when writing to RHEV because the effective user isn't able to chdir to the
    # current working directory. To guard against this, and because we don't use
    # the current working directory for anything, we set chdir to /tmp before we
    # start.
    chdir('/tmp');

    # Don't buffer output
    # While perl will use line buffering when STDOUT is connected to a tty, when
    # not connected to a tty, for example when invoked directly over ssh, it
    # will use a regular, large output buffer. This results in messages being
    # held in the buffer indefinitely.
    STDOUT->autoflush(1);

    # Read the config file
    $config = Sys::VirtConvert::Config->new
        ('/etc/virt-v2v.conf', '/var/lib/virt-v2v/virt-v2v.db');

    # Send our identification string
    print "VIRT_P2V_SERVER ".$Sys::VirtConvert::VERSION."\n";

    my $converted = 0;

    my $msg;
    while ($msg = p2v_receive()) {
        my $type = $msg->{type};

        # VERSION n
        if ($type eq MSG_VERSION) {
            my $version = $msg->{args}[0];
            if ($version <= VERSION) {
                p2v_return_ok();
            }

            else {
                die(__x('This version of virt-p2v-server does not '.
                        "support protocol version {version}.\n",
                        version => $version));
            }
        }

        # LANG lang
        elsif ($type eq MSG_LANG) {
            $ENV{LANG} = $msg->{args}[0];
            p2v_return_ok();
        }

        # METADATA length
        #  length bytes of YAML
        elsif ($type eq MSG_METADATA) {
            my $yaml = p2v_read($msg->{args}[0]);
            eval { $meta = Load($yaml); };
            die('Error parsing metadata: '.$@."\n") if $@;

            p2v_return_ok();
        }

        # PATH length path
        #   N.B. path could theoretically include spaces
        elsif ($type eq MSG_PATH) {
            my $length = $msg->{args}[0];

            my $path = join(' ', @{$msg->{args}}[1..$#{$msg->{args}}]);
            receive_path($path, $length);
        }

        # CONVERT
        elsif ($type eq MSG_CONVERT) {
            convert();
            $converted = 1;
        }

        # LIST_PROFILES
        elsif ($type eq MSG_LIST_PROFILES) {
            p2v_return_list($config->list_profiles());
        }

        # SET_PROFILE profile
        elsif ($type eq MSG_SET_PROFILE) {
            set_profile($msg->{args}[0]);
        }

        else {
            unexpected_msg($type);
        }
    }

    unexpected_close() unless $converted;
};

# Wrap any unwrapped error
if ($@) {
    p2v_return_err($@);
    v2vdie $@;
}

exit(0);

# Receive an image file
sub receive_path
{
    my ($path, $length) = @_;

    die("PATH without prior SET_PROFILE command\n")
        unless defined($target);
    die("PATH without prior METADATA command\n")
        unless defined($meta);

    my ($disk) = grep { $_->{path} eq $path } @{$meta->{disks}};
    die("$path not found in metadata\n") unless defined($disk);

    # Construct a volume name based on the path and hostname
    my $name = $meta->{name}.'-'.$disk->{device};
    $name =~ s,/,_,g;       # e.g. cciss devices have a directory structure

    $disk->{src} = new Sys::VirtConvert::Connection::Volume
        ($name, 'raw', $path, $length, $length, 0, 1, undef);

    my $sopts = $config->get_storage_opts();

    my $convert = 0;
    my $format;
    my $sparse;

    # Default to raw. Conversion required for anything else.
    if (!exists($sopts->{format}) || $sopts->{format} eq 'raw') {
        $format = 'raw';
    } else {
        $format = $sopts->{format};
        $convert = 1;
    }

    # Default to non-sparse
    my $allocation = $sopts->{allocation};
    if (!defined($allocation) || $allocation eq 'preallocated') {
        $sparse = 0;
    } elsif ($allocation eq 'sparse') {
        $sparse = 1;
    } else {
        die(__x("Invalid allocation policy {policy} in profile.\n",
                policy => $allocation));
    }

    # Create the target volume
    my $vol = $target->create_volume(
            $name,
            $format,
            $length,
            $sparse
        );
    p2v_return_ok();

    $disk->{dst} = $vol;

    # Receive an initial container
    my $msg = p2v_receive();
    unexpected_close() unless defined($msg);
    unexpected_msg($msg->{type}) unless $msg->{type} eq MSG_CONTAINER;

    # We only support RAW container
    my $ctype = $msg->{args}[0];
    die("Received unknown container type: $ctype\n") unless $ctype eq CONT_RAW;
    p2v_return_ok();

    # Update the disk entry with the new volume details
    $disk->{local_path} = $vol->get_local_path();
    $disk->{path} = $vol->get_path();
    $disk->{is_block} = $vol->is_block();

    my $writer = $vol->get_write_stream($convert);

    # Receive volume data in chunks
    my $received = 0;
    while ($received < $length) {
        my $data = p2v_receive();
        unexpected_close() unless defined($data);
        unexpected_msg($data->command) unless $data->{type} eq MSG_DATA;

        # Read the data message in chunks of up to 4M
        my $remaining = $data->{args}[0];
        while ($remaining > 0) {
            my $chunk = $remaining > 4*1024*1024 ? 4*1024*1024 : $remaining;
            my $buf = p2v_read($chunk);

            $received += $chunk;
            $remaining -= $chunk;

            $writer->write($buf);
        }

        # Close explicitly here in case there's any error.
        $writer->close();

        p2v_return_ok();
    }
}

# Use the specified profile
sub set_profile
{
    my ($profile) = @_;

    # Check the profile is in our list
    my $found = 0;
    for my $i ($config->list_profiles()) {
        if ($i eq $profile) {
            $found = 1;
            last;
        }
    }
    die(__x("Invalid profile: {profile}\n", profile => $profile))
        unless ($found);

    $config->use_profile($profile);

    my $storage = $config->get_storage();
    my $method = $config->get_method();
    if ($method eq 'libvirt') {
        $target = new Sys::VirtConvert::Connection::LibVirtTarget
            ('qemu:///system', $storage);
    } elsif ($method eq 'rhev') {
        $target = new Sys::VirtConvert::Connection::RHEVTarget($storage);
    } else {
        die(__x("Profile {profile} specifies invalid method {method}.\n",
                profile => $profile, method => $method));
    }

    p2v_return_ok();
}

sub convert
{
    die("CONVERT without prior SET_PROFILE command\n") unless defined($target);
    die("CONVERT without prior METADATA command\n") unless defined($meta);

    my $g;
    eval {
        my $transferiso = $config->get_transfer_iso();

        $g = new Sys::VirtConvert::GuestfsHandle(
            $meta->{disks},
            $transferiso,
            $target->isa('Sys::VirtConvert::Connection::RHEVTarget')
        );

        my $transferdev;
        if (defined($transferiso)) {
            my @devices = $g->list_devices();
            $transferdev = pop(@devices);
        }

        my $root = inspect_guest($g, $transferdev);
        my $guestcaps =
            Sys::VirtConvert::Converter->convert($g, $config, $root, $meta);
        $target->create_guest($g, $root, $meta, $config, $guestcaps,
                              $meta->{name});

        if($guestcaps->{block} eq 'virtio' && $guestcaps->{net} eq 'virtio') {
            logmsg NOTICE, __x('{name} configured with virtio drivers.',
                               name => $meta->{name});
        } elsif ($guestcaps->{block} eq 'virtio') {
            logmsg NOTICE, __x('{name} configured with virtio storage only.',
                               name => $meta->{name});
        } elsif ($guestcaps->{net} eq 'virtio') {
            logmsg NOTICE, __x('{name} configured with virtio networking only.',
                               name => $meta->{name});
        } else {
            logmsg NOTICE, __x('{name} configured without virtio drivers.',
                               name => $meta->{name});
        }
    };

    # If any of the above commands result in failure, we need to ensure that
    # the guestfs qemu process is cleaned up before further cleanup. Failure to
    # do this can result in failure to umount RHEV export's temporary mount
    # point.
    if ($@) {
        my $err = $@;
        $g->close() if defined($g);

        die($@);
    }

    p2v_return_ok();
}

sub unexpected_msg
{
    die('Received unexpected command: '.shift."\n");
}

sub unexpected_close
{
    die __("Client closed connection unexpectedly.\n");
}

END {
    my $err = $?;

    # Delete the stderr log file if it's empty
    if (defined($stderr)) {
        use Fcntl 'SEEK_CUR';
        my $stderr_pos = sysseek($stderr, 0, SEEK_CUR);
        if ($stderr_pos == 0) {
            unlink($stderr_filename);
        } else {
            logmsg WARN, __x('Error messages were written to {file}.',
                             file => $stderr_filename);
        }
    }

    logmsg NOTICE, __x("{program} exited.", program => 'p2v-server');

    # die() sets $? to 255, which is untidy.
    $? = $err == 255 ? 1 : $err;
}

# Perform guest inspection using the libguestfs core inspection API.
# Returns the root device of the os to be converted.
sub inspect_guest
{
    my $g = shift;
    my $transferdev = shift;

    # Get list of roots, sorted
    my @roots = $g->inspect_os();

    # Filter out the transfer device from the results of inspect_os
    # There's a libguestfs bug (fixed upstream) which meant the transfer ISO
    # could be erroneously detected as an unknown Windows OS. As we know what it
    # is, we can filter out the transfer device here. Even when the fix is
    # released this is reasonable belt & braces.
    @roots = grep(!/^\Q$transferdev\E$/, @roots) if defined($transferdev);

    @roots = sort @roots;

    # Only work on single-root operating systems.
    die __("No root device found in this operating system image.\n")
        if @roots == 0;

    die __("Multiboot operating systems are not supported.\n")
        if @roots > 1;

    return $roots[0];
}

sub p2v_receive
{
    my $in = <>;
    return undef unless defined($in);

    # Messages consist of the message type followed by 0 or more arguments,
    # terminated by a newline
    chomp($in);
    $in =~ /^([A-Z_]+)( .+)?$/ or die("Received invalid message: $in\n");

    my %msg;
    $msg{type} = $1;
    if (defined($2)) {
        my @args = split(' ', $2);
        $msg{args} =  \@args;
    } else {
        $msg{args} = [];
    }

    logmsg DEBUG, __x('Received: {command} {args}',
                      command => $msg{type},
                      args => join(' ', @{$msg{args}}));

    return \%msg;
}

sub p2v_read
{
    my ($length) = @_;

    my $buf;
    my $total = 0;

    while($total < $length) {
        my $in = read(STDIN, $buf, $length, $total)
            or die(__x("Error receiving data: {error}\n", error => $@));
        logmsg DEBUG, "Read $in bytes";
        $total += $in;
    }

    return $buf;
}

sub p2v_return_ok
{
    my $msg = "OK";
    logmsg DEBUG, __x('Sent: {msg}', msg => $msg);
    print $msg,"\n";
}

sub p2v_return_list
{
    my @values = @_;

    my $msg = 'LIST '.scalar(@values);
    foreach my $value (@values) {
        $msg .= "\n$value";
    }
    logmsg DEBUG, __x('Sent: {msg}', msg => $msg);
    print $msg,"\n";
}

sub p2v_return_err
{
    my $msg = 'ERROR '.shift;
    logmsg DEBUG, __x('Sent: {msg}', msg => $msg);
    print $msg,"\n";
}

=head1 SEE ALSO

L<virt-v2v(1)>,
L<http://libguestfs.org/>.

=head1 AUTHOR

Matthew Booth <mbooth@redhat.com>

=head1 COPYRIGHT

Copyright (C) 2011 Red Hat Inc.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
