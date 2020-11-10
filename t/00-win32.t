use strict;
use warnings;

use Test::More;
use AnyEvent;
use Carp;
use Guard qw(scope_guard);
use IPC::Simple;

my $code = '$|=1; warn "starting\n"; print "hello world\n";';

$code =~ s/"/\\"/g;
$code = "binmode(STDERR); binmode(STDOUT); binmode(STDIN); $code";
$code = '"'.$code.'"';

system('perl', '-e', $code);

ok 1, 'placeholder';
done_testing;
