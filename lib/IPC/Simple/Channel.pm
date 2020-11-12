package IPC::Simple::Channel;

use strict;
use warnings;

use AnyEvent;

sub new {
  my ($class) = @_;

  bless{
    waiters     => [],
    buffer      => [],
    is_shutdown => 0,
  }, $class;
}

sub DESTROY {
  my $self = shift;
  $self->shutdown;
}

sub shutdown {
  my $self = shift;

  $self->{is_shutdown} = 1;

  # flush any remaining messages that have pending receivers
  $self->flush;

  # send undef to any remaining receivers
  $_->send for @{ $self->{waiters} };
}

sub size {
  my $self = shift;
  return scalar @{ $self->{buffer} };
}

sub put {
  my $self = shift;
  push @{ $self->{buffer} }, @_;
  $self->flush;
  return $self->{size};
}

sub get {
  my $self = shift;
  $self->async->recv;
}

sub recv {
  my $self = shift;
  $self->async->recv;
}

sub next {
  my $self = shift;
  $self->async->recv;
}

sub async {
  my $self = shift;
  my $cv = AnyEvent->condvar;

  if ($self->{is_shutdown}) {
    my $msg = shift @{ $self->{buffer} };
    $cv->send($msg);
    return $cv;
  }
  else {
    push @{ $self->{waiters} }, $cv;
    $self->flush;
    return $cv;
  }
}

sub flush {
  my $self = shift;
  while (@{ $self->{waiters} } && @{ $self->{buffer} }) {
    my $cv = shift @{ $self->{waiters} };
    $cv->send( shift @{ $self->{buffer} } );
  }
}

1;
