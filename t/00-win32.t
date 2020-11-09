use strict;
use warnings;

#use Test::More;
use AnyEvent;
use Test2::V0;
use Symbol qw(gensym);
use IPC::Open3 qw(open3);

my $perl = q{$|=1; binmode STDOUT, \"text\"; binmode STDERR, \"text\"; warn \"starting\n\"; while (my $line = <STDIN>) { print(\"$line\") }};

unless (AnyEvent::WIN32) {
  $perl =~ s/\$/\\\$/g;
}

my $code = qq{perl -e "$perl"};
diag "code=$code";
my $pid = open3(my $in, my $out, my $err = gensym, $code) or die $!;

print $out "hello world\r\n";

my $rs = waitpid $pid, 0;
diag "waitpid=$rs, status=$?";

my $error = <$err>;
diag "err=$error";

my $line = <$out>;

is $line, "hello world\n", 'stdout';

done_testing;
