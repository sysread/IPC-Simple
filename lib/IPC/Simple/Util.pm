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
    warn "<$pkg : $line> $msg\n";
  }
}

1;
