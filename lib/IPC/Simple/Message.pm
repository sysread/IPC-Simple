package IPC::Simple::Message;

use strict;
use warnings;

use Moo;
use Types::Standard -types;

use overload fallback => 1,
  '""' => sub{
    my $self = shift;
    return $self->message;
  },
  '==' => sub{
    my ($self, $other, $swap) = @_;

    if ($swap) {
      ($self, $other) = ($other, $self);
    }

    return $self->source == $other;
  };

use constant IPC_STDOUT => 1;
use constant IPC_STDERR => 2;
use constant IPC_ERROR  => 3;

BEGIN{
  extends 'Exporter';

  our @EXPORT = qw(
    IPC_STDOUT
    IPC_STDERR
    IPC_ERROR
  );
}

has source =>
  is => 'ro',
  isa => Enum[IPC_STDOUT, IPC_STDERR, IPC_ERROR],
  required => 1;

has message =>
  is => 'ro',
  isa => Str,
  required => 1;

sub stdout { $_[0] == IPC_STDOUT }
sub stderr { $_[0] == IPC_STDERR }
sub error  { $_[0] == IPC_ERROR }

1;
