use strict;
use warnings;

use Test::More;
use AnyEvent;
use Carp;
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
    confess 'timeout reached';
  },
);

my $cv = AnyEvent->condvar;
$proc->send('test message');
$proc->async($cv);
is $cv->recv, 'test message';

# clear timeout so it won't go off
undef $timeout;

done_testing;
