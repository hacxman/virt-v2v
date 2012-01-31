# Sys::VirtConvert::Transfer::SSH
# Copyright (C) 2010 Red Hat Inc.
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

package Sys::VirtConvert::Transfer::SSH::Stream;

use Sys::VirtConvert::Util;
use Locale::TextDomain 'virt-v2v';

sub new
{
    my $class = shift;
    my ($hostname, $username, $command) = @_;

    my $self = {};
    bless($self, $class);

    my ($stdin_read, $stdin_write);
    my ($stdout_read, $stdout_write);
    my ($stderr_read, $stderr_write);

    pipe($stdin_read, $stdin_write);
    pipe($stdout_read, $stdout_write);
    pipe($stderr_read, $stderr_write);

    my $pid = fork();
    if ($pid == 0) {
        my @command;
        push(@command, 'ssh', '-q');
        push(@command, '-l', $username) if (defined($username));
        push(@command, $hostname);
        push(@command, $command);

        # Close the ends of the pipes we don't need
        close($stdin_write);
        close($stdout_read);
        close($stderr_read);

        # dup2() stdin, stdout and stderr to pipes
        open(STDIN, "<&".fileno($stdin_read))
            or die("dup stdin failed: $!");
        open(STDOUT, "<&".fileno($stdout_write))
            or die("dup stdout failed: $!");
        open(STDERR, "<&".fileno($stderr_write))
            or die("dup stderr failed: $!");

        # We parse stderr, so make sure it's in English
        $ENV{LANG} = 'C';
        exec(@command);
    }

    close($stdin_read);
    close($stdout_write);
    close($stderr_write);

    $self->{pid}    = $pid;
    $self->{stdin}  = $stdin_write;
    $self->{stdout} = $stdout_read;
    $self->{stderr} = $stderr_read;

    $self->{hostname} = $hostname;

    return $self;
}

sub close
{
    my $self = shift;

    # Nothing to do if it's already closed.
    return unless (exists($self->{pid}));

    my $pid    = $self->{pid};
    my $stderr = $self->{stderr};

    # Must close stdin before waitpid, or process will not exit when writing
    close($self->{stdin});
    close($self->{stdout});

    waitpid($pid, 0) == $pid or die("error reaping child: $!");
    delete($self->{pid});

    # Check if the child returned an error
    # Don't report an error if we're exiting due to a user signal
    # N.B. WIFSIGNALED($?) doesn't seem to work as expected here
    if ($? != 0 && !$main::signal_exit) {
        my $output = "";
        while (<$stderr>) {
            $output .= $_;
        }

        my $msg = __x("Unexpected error copying {path} from {host}.",
                      path => $self->{path},
                      host => $self->{hostname});
        if (length($output) > 0) {
            $msg .= "\n";
            $msg .= __x("Command output: {output}", output => $output);
        }
        v2vdie $msg;
    }

    close($self->{stderr});

    delete($self->{stdin});
    delete($self->{stdout});
    delete($self->{stderr});
}

sub DESTROY
{
    my $self = shift;

    # Preserve error, which will be overwritten by waitpid
    my $err = $?;

    $self->close();

    $? |= $err;
}

sub _check_stderr
{
    my $self = shift;
    my ($rw, $errfun) = @_;

    for(;;) {
        my ($rin, $rout, $win, $wout);
        $rin = '';
        vec($rin, fileno($self->{stderr}), 1) = 1;

        # Waiting to read from stdout
        if ($rw == 0) {
            $win = undef;
            vec($rin, fileno($self->{stdout}), 1) = 1;
        }

        # Waiting to write to stdin
        else {
            $win = '';
            vec($win, fileno($self->{stdin}), 1) = 1;
        }

        my $nfound = select($rout=$rin, $wout=$win, undef, undef);
        die("select failed: $!") if ($nfound < 0);

        my $stderr = $self->{stderr};
        if (vec($rout, fileno($stderr), 1) == 1) {
            my $error = '';
            while(<$stderr>) {
                $error .= $_;
            }

            &$errfun($error);
        }

        last if (vec($rout, fileno($self->{stdout}), 1) == 1 ||
                 vec($wout, fileno($self->{stdin}), 1) == 1);
    }
}

package Sys::VirtConvert::Transfer::SSH::ReadStream;

use Sys::VirtConvert::Util;
use Locale::TextDomain 'virt-v2v';

@Sys::VirtConvert::Transfer::SSH::ReadStream::ISA =
    qw(Sys::VirtConvert::Transfer::SSH::Stream);

sub new
{
    my $class = shift;
    my ($path, $hostname, $username, $is_sparse, $is_block) = @_;

    my $sizecmd;
    if ($is_block) {
        $sizecmd = "blockdev --getsize64 $path";
    } else {
        $sizecmd = "stat -c %s $path";
    }

    my $self = $class->SUPER::new($hostname, $username, "$sizecmd;dd if=$path");

    $self->{path} = $path;

    # Check that the stream becomes readable without anything on stderr
    $self->SUPER::_check_stderr(0, sub { $self->_read_error(@_) } );

    # Read the file size
    my $stdout = $self->{stdout};
    $self->{size} = <$stdout>;

    return $self;
}

sub read
{
    my $self = shift;
    my ($size) = @_;

    my $buf;
    my $in = read($self->{stdout}, $buf, $size);
    $self->_read_error($!) unless (defined($in));

    return "" if ($in == 0);
    return $buf;
}

sub _read_error
{
    my $self = shift;
    my ($error) = @_;

    v2vdie __x('Error reading from {path}: {error}',
               path => $self->{path}, error => $error);
}

sub _get_size
{
    return shift->{size};
}

package Sys::VirtConvert::Transfer::SSH::WriteStream;

use Sys::VirtConvert::Util;
use Locale::TextDomain 'virt-v2v';

@Sys::VirtConvert::Transfer::SSH::WriteStream::ISA =
    qw(Sys::VirtConvert::Transfer::SSH::Stream);

sub new
{
    my $class = shift;
    my ($path, $hostname, $username, $is_sparse) = @_;

    my $self = $class->SUPER::new($hostname, $username, "dd of=$path");

    $self->{path} = $path;

    # Check that the stream becomes writable without anything on stderr
    $self->SUPER::_check_stderr(1, sub { $self->_write_error(@_) });

    return $self;
}

sub write
{
    my $self = shift;
    my ($buf) = @_;

    print { $self->{stdin} } $buf or $self->_write_error($!);
}

sub _write_error
{
    my $self = shift;
    my ($error) = @_;

    v2vdie __x('Error writing data to {path}: {error}',
               path => $self->{path}, error => $error);
}

package Sys::VirtConvert::Transfer::SSH;

use File::Spec;
use File::stat;
use File::Temp;
use Term::ProgressBar;

use Sys::VirtConvert::Util;
use Sys::VirtConvert::Transfer::Local;
use Locale::TextDomain 'virt-v2v';

=pod

=head1 NAME

Sys::VirtConvert::Transfer::SSH - Transfer data over an SSH connection

=head1 METHODS

=over

=item new(path, hostname, username, is_sparse, is_block)

Create a new SSH transfer object.

=cut

sub new
{
    my $class = shift;
    my ($name, $path, $format, $hostname, $username,
        $is_sparse, $is_block) = @_;

    my $self = {};
    bless($self, $class);

    $self->{name}      = $name;
    $self->{path}      = $path;
    $self->{format}    = $format;
    $self->{hostname}  = $hostname;
    $self->{username}  = $username;
    $self->{is_sparse} = $is_sparse;
    $self->{is_block}  = $is_block;

    return $self;
}

=item local_path

SSH cannot currently return a local path. This function will die().

=cut

sub local_path
{
    v2vdie __('virt-v2v cannot yet write to an SSH connection');
}

=item get_read_stream(convert)

Get a ReadStream for this volume. Data will be converted to raw format if
I<convert> is 1.

=cut

sub get_read_stream
{
    my $self = shift;
    my ($convert) = @_;

    if ($convert && $self->{format} ne 'raw') {
        # We need to copy the file locally to convert it
        my $cache = new File::Temp;

        my $t = new Sys::VirtConvert::Transfer::SSH::ReadStream(
            $self->{path},
            $self->{hostname},
            $self->{username},
            $self->{is_sparse},
            $self->{is_block}
        );

        # Initialize a progress bar if STDERR is on a tty
        my $progress;
        if (-t STDERR) {
            my $name = __x('Caching {name}', name => $self->{name});
            $progress = new Term::ProgressBar({name => $name,
                                               count => $t->_get_size(),
                                               ETA => 'linear' });
        } else {
            logmsg NOTICE, __x('Caching {name}: {size} bytes',
                               name => $self->{name}, size => $t->_get_size());
        }

        my $total = 0;
        my $next_update = 0;
        for (;;) {
            my $buf = $t->read(4 * 1024 * 1024);
            last if (length($buf) == 0);

            $total += length($buf);
            print $cache $buf;

            $next_update = $progress->update($total)
                if (defined($progress) && $total > $next_update);
        }
        if (defined($progress)) {
            # Indicate that we finished regardless of how much data was written
            $progress->update($t->_get_size());
            # The progress bar doesn't print a newline on completion
            print STDERR "\n";
        }

        $t->close();
        $cache->close();

        my $local = new Sys::VirtConvert::Transfer::Local($cache->filename(), 0,
                                                          $self->{format},
                                                          $self->{is_sparse});
        return $local->get_read_stream($convert);
    }

    else {
        return new Sys::VirtConvert::Transfer::SSH::ReadStream(
            $self->{path},
            $self->{hostname},
            $self->{username},
            $self->{is_sparse},
            $self->{is_block}
        );
    }
}

=item get_write_stream(convert)

Get a WriteStream for this volume. Data will be converted from raw format if
I<convert> is 1.

=cut

sub get_write_stream
{
    my $self = shift;
    my ($convert) = @_;

    v2vdie __('When writing to an SSH connection, virt-v2v can only '.
              'currently convert volumes to raw format')
        if $convert && $self->{format} ne 'raw';

    return new Sys::VirtConvert::Transfer::SSH::WriteStream(
        $self->{path},
        $self->{hostname},
        $self->{username},
        $self->{is_sparse}
    );
}

=back

=head1 COPYRIGHT

Copyright (C) 2010 Red Hat Inc.

=head1 LICENSE

Please see the file COPYING.LIB for the full license.

=head1 SEE ALSO

L<virt-v2v(1)>,
L<http://libguestfs.org/>.

=cut

1;
