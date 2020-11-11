use strict;
use warnings;

use Test::More;
use AnyEvent;
use Carp;
use IPC::Simple;

BAIL_OUT 'OS unsupported' if $^O eq 'MSWin32';

my $proc = IPC::Simple->new(cmd => ['perl', '-e', 'sleep 10']);

# Start a timer to ensure a bug doesn't cause us to run indefinitely
my $timeout = AnyEvent->timer(
  after => 10,
  cb => sub{
    diag 'timeout reached';
    $proc->terminate;
    die 'timeout reached';
  },
);

ok $proc->launch, 'launch';

$proc->terminate;
ok $proc->is_stopping, 'is_stopping';

$proc->join;
ok $proc->is_ready, 'is_ready';

is $proc->exit_code, 0, 'exit_code';

undef $timeout; # clear timeout so it won't go off

done_testing;
