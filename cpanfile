requires 'AnyEvent::Handle' => '0';
requires 'AnyEvent'         => '0';
requires 'Carp'             => '0';
requires 'Exporter'         => '0';
requires 'Fcntl'            => '0';
requires 'IPC::Open3'       => '0';
requires 'Moo'              => '0';
requires 'POSIX'            => '0';
requires 'Scalar::Util'     => '0';
requires 'Symbol'           => '0';
requires 'Types::Standard'  => '0';

on test => sub{
  requires 'Test::More' => '0';
};
