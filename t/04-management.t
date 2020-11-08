use strict;
use warnings;

use Test::More;
use AnyEvent;
use Carp;
use IPC::Simple;
use Guard qw(scope_guard);

ok my $proc = IPC::Simple->new(
  cmd  => 'perl',
  args => ['-e', 'local $|=1; while (my $line = <STDIN>) { print("$line") }'],
), 'ctor';

# Start a timer to ensure a bug doesn't cause us to run indefinitely
my $timeout = AnyEvent->timer(
  after => 10,
  cb => sub{
    $proc->terminate;
    confess 'timeout reached';
  },
);

scope_guard{
  undef $timeout; # clear timeout so it won't go off
};


ok $proc->launch, 'launch';

$proc->terminate;
ok $proc->is_stopping, 'is_stopping';

$proc->join;
ok $proc->is_ready, 'is_ready';

is $proc->exit_code, 0, 'exit_code';

done_testing;
