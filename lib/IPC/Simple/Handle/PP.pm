package IPC::Simple::Handle::PP;

use strict;
use warnings;

use Carp;
use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

use constant DEFAULT_CHUNK_SIZE => 128;

sub new {
  my ($class, %param) = @_;
  my $fh  = $param{fh}  || croak 'expected parameter "fh"';
  my $eol = $param{eol} || croak 'expected parameter "eol"';

  $class->set_nonblocking($fh);

  bless{
    fh         => $fh,
    eol        => $eol,
    in_buffer  => '',
    out_buffer => '',
    offset     => 0,
    closed     => 0,
    error      => undef,
  }, $class;
}

#-------------------------------------------------------------------------------
# Accessors
#-------------------------------------------------------------------------------
sub is_closed { $_[0]->{closed} }
sub error     { $_[0]->{error} }

sub set_nonblocking {
  my ($class, $fh) = @_;

  # Get any existing flags on the handle
  my $flags = fcntl $fh, F_GETFL, 0
    or die $!;

  # Set the non-blocking bit
  fcntl $fh, F_SETFL, $flags | O_NONBLOCK
    or die $!;
}

sub close {
  my $self = shift;

  unless ($self->{closed}) {
    close $self->{fh};
    $self->{closed} = 1;
  }
}
#-------------------------------------------------------------------------------
# Appends $data to the write buffer so that it is available for write_bytes.
#-------------------------------------------------------------------------------
sub queue_write {
  my ($self, $data) = @_;
  $self->{out_buffer} .= $data;
}

#-------------------------------------------------------------------------------
# Writes up to DEFAULT_CHUNK_SIZE bytes to the file handle and removes them
# from the out_buffer. If fewer bytes are available to write or the handle is
# unable to receive that many bytes, only those bytes that are written are
# removed from the buffer.
#-------------------------------------------------------------------------------
sub write_bytes {
  my $self = shift;
  my $size = shift || DEFAULT_CHUNK_SIZE;

  croak 'cannot write to a closed file handle'
    if $self->{closed};

  my $bytes;

  local $SIG{PIPE} = sub{ die "sigpipe\n" };
  local $SIG{CHLD} = sub{ die "sigchld\n" };

  if (length $self->{out_buffer} > 0) {
    $bytes = eval{ syswrite $self->{fh}, $self->{out_buffer}, $size };

    # An uncaught error occurred during the write
    if ($@) {
      $self->{error} = $@;
      $self->close;
    }
    # An error occurred during the write that perl caught
    elsif (!defined $bytes) {
      $self->{error} = $!;
      $self->close;
    }
    # Wrote some bytes
    elsif ($bytes > 0) {
      substr($self->{out_buffer}, 0, $bytes) = '';
    }
    # Nothign to do
    else {
      ;
    }
  }
  else {
    $bytes = 0;
  }

  return $bytes;
}

#-------------------------------------------------------------------------------
# Reads up to DEFAULT_CHUNK_SIZE off the file handle and appends them to
# $self->{in_buffer}, increasing $self->{offset} accordingly.
#-------------------------------------------------------------------------------
sub read_bytes {
  my $self = shift;
  my $size = shift || DEFAULT_CHUNK_SIZE;

  croak 'cannot read from a closed file handle'
    if $self->{closed};

  my $bytes = eval{ sysread $self->{fh}, $self->{in_buffer}, $size, $self->{offset} };

  # An uncaught error occurred during the read
  if ($@) {
    $self->{error} = $@;
    $self->close;
  }
  # An error occurred during the read that perl caught
  elsif (!defined $bytes) {
    $self->{error} = $!;
    $self->close;
  }
  # Successful read
  elsif ($bytes > 0) {
    $self->{offset} += $bytes;
  }
  # No bytes ready to read
  else {
    ; # nothing to do
  }

  return $bytes;
}

#-------------------------------------------------------------------------------
# Removes lines (strings terminating in $self->{eol}) off of the front of the
# buffer, reducing $self->{offset} as needed. Returns an array ref of lines
# removed from the buffer.
#-------------------------------------------------------------------------------
sub flush {
  my $self = shift;
  my @lines;

  while ($self->{offset} > 0) {
    my $idx = index $self->{in_buffer}, $self->{eol};

    if ($idx == -1) {
      last;
    }

    my $len_eol = length $self->{eol};
    my $line = substr $self->{in_buffer}, 0, $idx + 1 - $len_eol;

    substr($self->{in_buffer}, 0, $idx + 1) = '';
    $self->{offset} -= $idx + 1;

    push @lines, $line;
  }

  return \@lines;
}

1;
