use strict;
use warnings;

use Test::More;
use IPC::Simple;
use Guard qw(scope_guard);

ok my $proc = IPC::Simple->new(
  cmd  => 'perl',
  args => ['-e', 'local $|=1; while (my $line = <STDIN>) { print("$line") }'],
), 'ctor';

scope_guard{
  $proc->terminate; # send kill signal
  $proc->join;      # wait for process to complete
};

ok !$proc->is_running, 'is_running is initially false';
ok $proc->launch, 'launch';
ok $proc->is_running, 'is_running is true after launch';

done_testing;
