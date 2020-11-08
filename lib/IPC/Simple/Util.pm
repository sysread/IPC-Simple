package IPC::Simple::Util;

use strict;
use warnings;

use parent 'Exporter';

our @EXPORT = qw(
  debug
);

sub debug {
  if ($ENV{IPC_SIMPLE_DEBUG}) {
    my $msg = sprintf shift, @_;
    my ($pkg, $file, $line) = caller;
    my $ts = time;
    warn "<$pkg:$line | $ts> $msg\n";
  }
}

1;
