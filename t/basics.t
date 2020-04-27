use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Compare qw(bag item end);
use AnyEvent;
use IPC::Simple;

ok my $proc = IPC::Simple->new(
  cmd  => 'perl',
  args => ['-e', 'local $|=1; warn "starting\n"; while (my $line = <STDIN>) { print("$line") }'],
), 'ctor';

# Start a timer to ensure a bug doesn't cause us to run indefinitely
my $timeout = AnyEvent->timer(
  after => 30,
  cb => sub{
    $proc->terminate;
    die 'timeout reached';
  },
);

ok !$proc->is_running, 'is_running is initially false';
ok $proc->launch, 'launch';
ok $proc->is_running, 'is_running is true after launch';

ok $proc->send('hello world'), 'send';

my $msgs = [];
push @$msgs, $proc->recv;
push @$msgs, $proc->recv;

is $msgs, bag{
  item ['starting', IPC_STDERR];
  item ['hello world', IPC_STDOUT];
}, 'recv';

$proc->terminate;
ok $proc->is_stopping, 'is_stopping';

$proc->join;
ok $proc->is_ready, 'is_ready';

is $proc->exit_code, 0, 'exit_code';

undef $timeout;

done_testing;