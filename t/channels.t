use strict;
use warnings;

use Test::More;
use AnyEvent;
use Carp;
use Guard qw(scope_guard);
use IPC::Simple;

BAIL_OUT 'OS unsupported' if $^O eq 'MSWin32';

my $proc = IPC::Simple->new(
  cmd  => 'perl',
  args => ['-e', '$|=1; while (defined(<STDIN>)) { warn "stderr message\n"; print "stdout message\n"; }'],
);

$proc->launch;

my $stdout = $proc->stdout;
my $stderr = $proc->stderr;
my $errors = $proc->errors;

$proc->send(1);
is $stderr->recv, 'stderr message', 'stderr';
is $stdout->recv, 'stdout message', 'stdout';

$proc->terminate;
$proc->join;

done_testing;
