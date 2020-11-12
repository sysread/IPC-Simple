use strict;
use warnings;

use Test::More;
use IPC::Simple::Handle::PP;

BAIL_OUT 'OS unsupported' if $^O eq 'MSWin32';

subtest flush => sub{
  my $mock = {
    eol       => ':',
    in_buffer => '',
    offset    => 0,
  };

  subtest 'empty buffer' => sub{
    is_deeply IPC::Simple::Handle::PP::flush($mock), [], 'result';
    is $mock->{in_buffer}, '', 'in_buffer';
    is $mock->{offset}, 0, 'offset';
  };

  subtest 'partial line' => sub{
    $mock->{in_buffer} = 'a';
    $mock->{offset} = 1;

    is_deeply IPC::Simple::Handle::PP::flush($mock), [], 'result';
    is $mock->{in_buffer}, 'a', 'in_buffer';
    is $mock->{offset}, 1, 'offset';
  };

  subtest 'single line' => sub{
    $mock->{in_buffer} = 'fnord:';
    $mock->{offset} = 6;

    is_deeply IPC::Simple::Handle::PP::flush($mock), ['fnord'], 'result';
    is $mock->{in_buffer}, '', 'in_buffer';
    is $mock->{offset}, 0, 'offset';
  };

  subtest 'multiple lines' => sub{
    $mock->{in_buffer} = 'fnord:slack:';
    $mock->{offset} = 12;

    is_deeply IPC::Simple::Handle::PP::flush($mock), ['fnord', 'slack'], 'result';
    is $mock->{in_buffer}, '', 'in_buffer';
    is $mock->{offset}, 0, 'offset';
  };

  subtest 'multiple lines w/ partial' => sub{
    $mock->{in_buffer} = 'fnord:slack:qwerty';
    $mock->{offset} = 18;

    is_deeply IPC::Simple::Handle::PP::flush($mock), ['fnord', 'slack'], 'result';
    is $mock->{in_buffer}, 'qwerty', 'in_buffer';
    is $mock->{offset}, 6, 'offset';
  };
};


subtest read_bytes => sub{
  my $pid = open my $fh, '-|', 'perl -e "$|=1; print qq{fnord\n};"'
    or die $!;

  my $handle = IPC::Simple::Handle::PP->new(fh => $fh, eol => "\n");

  waitpid $pid, 0;

  subtest 'chunk size < bytes available' => sub{
    is $handle->read_bytes(4), 4, 'bytes';
    is $handle->{in_buffer}, "fnor", 'in_buffer';
    is $handle->{offset}, 4, 'offset';
    ok !$handle->is_closed, 'is_closed';
  };

  subtest 'chunk size > bytes available' => sub{
    is $handle->read_bytes(4), 2, 'bytes';
    is $handle->{in_buffer}, "fnord\n", 'in_buffer';
    is $handle->{offset}, 6, 'offset';
    ok !$handle->is_closed, 'is_closed';
  };

  subtest 'no bytes available' => sub{
    is $handle->read_bytes(1), 0, 'bytes';
    is $handle->{in_buffer}, "fnord\n", 'in_buffer';
    is $handle->{offset}, 6, 'offset';
    ok !$handle->is_closed, 'is_closed';
  };

  subtest 'read error' => sub{
    close $fh;
    is $handle->read_bytes(1), undef, 'bytes';
    is $handle->{in_buffer}, "fnord\n", 'in_buffer';
    is $handle->{offset}, 6, 'offset';
    ok $handle->is_closed, 'is_closed';
    like $handle->error, qr/bad file descriptor/i, 'error';
  };

  eval{ $handle->read_bytes };
  like $@, qr/cannot read from a closed file handle/, 'closed handle';
};


subtest write_bytes => sub{
  my $pid = open my $fh, '|-', 'perl -e "1 while <STDIN>"'
    or die $!;

  my $handle = IPC::Simple::Handle::PP->new(fh => $fh, eol => "\n");

  is $handle->write_bytes, 0, 'nothing to write';

  subtest 'partial write' => sub{
    $handle->queue_write("fnord\n");
    is $handle->write_bytes(3), 3, 'bytes';
    is $handle->{out_buffer}, "rd\n", 'out_buffer';
    ok !$handle->is_closed, 'is_closed';
  };

  subtest 'chunk size > buffer size' => sub{
    is $handle->write_bytes(10), 3, 'bytes';
    is $handle->{out_buffer}, '', 'out_buffer';
    ok !$handle->is_closed, 'is_closed';
  };

#-------------------------------------------------------------------------------
# TODO: How do I trigger a syswrite failure? Closing the handle doesn't seem
# to affect writes like it does reads.
#-------------------------------------------------------------------------------
#  subtest 'write error' => sub{
#    close $fh;
#    waitpid $pid, 0;
#
#    is $handle->write_bytes, undef, 'bytes';
#    is $handle->{out_buffer}, '', 'out_buffer';
#    ok $handle->is_closed, 'is_closed';
#    like $handle->error, qr/bad file descriptor/i, 'error';
#  };

  $handle->close;
  eval{ $handle->write_bytes };
  like $@, qr/cannot write to a closed file handle/, 'closed handle';
};


done_testing;
