package IPC::Simple::Message;

use strict;
use warnings;

use Moo;
use Types::Standard -types;

use overload fallback => 1,
  '""' => sub{
    my $self = shift;
    return $self->message;
  };

use constant IPC_STDIN  => 'stdin';
use constant IPC_STDOUT => 'stdout';
use constant IPC_STDERR => 'stderr';
use constant IPC_ERROR  => 'errors';

BEGIN{
  extends 'Exporter';

  our @EXPORT = qw(
    IPC_STDIN
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

sub stdout { $_[0]->source eq IPC_STDOUT }
sub stderr { $_[0]->source eq IPC_STDERR }
sub error  { $_[0]->source eq IPC_ERROR }

1;
