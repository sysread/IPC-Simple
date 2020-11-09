use strict;
use warnings;

use Test::More;
use AnyEvent::Util;

my $echo = 'perl -e "warn qq{starting\\n}; my \\$line = <STDIN>; print(\\$line)"; exit 0';
diag $echo;

my $stdin = "hello world\n";
my $stdout;
my $stderr;

my $cv = AnyEvent::Util::run_cmd(
  $echo,
  '<'  => \$stdin,
  '>'  => \$stdout,
  '2>' => \$stderr,
);

$cv->recv;

is $stderr, "starting\n";
is $stdout, "hello world\n";

done_testing;
