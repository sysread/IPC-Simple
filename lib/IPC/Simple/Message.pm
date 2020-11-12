package IPC::Simple::Message;

use strict;
use warnings;

use overload fallback => 1,
  '""' => \&message;

use constant IPC_STDIN  => 'stdin';
use constant IPC_STDOUT => 'stdout';
use constant IPC_STDERR => 'stderr';
use constant IPC_ERROR  => 'errors';

BEGIN{
  use base 'Exporter';

  our @EXPORT = qw(
    IPC_STDIN
    IPC_STDOUT
    IPC_STDERR
    IPC_ERROR
  );
}

sub new {
  my ($class, %param) = @_;

  bless{
    source  => $param{source},
    message => $param{message},
  }, $class;
}

sub source  { $_[0]->{source} }
sub message { $_[0]->{message} }
sub stdout  { $_[0]->source eq IPC_STDOUT }
sub stderr  { $_[0]->source eq IPC_STDERR }
sub error   { $_[0]->source eq IPC_ERROR }

1;
