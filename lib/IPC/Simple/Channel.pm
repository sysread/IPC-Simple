package IPC::Simple::Channel;

use strict;
use warnings;

use AnyEvent;
use Moo;
use Types::Standard -types;

has waiters =>
  is => 'ro',
  isa => ArrayRef[InstanceOf['AnyEvent::CondVar']],
  default => sub{ [] };

has buffer =>
  is => 'ro',
  isa => ArrayRef,
  default => sub{ [] };

has is_shutdown =>
  is => 'rw',
  isa => Bool,
  default => 0;

sub DEMOLISH {
  my $self = shift;
  $self->shutdown;
}

sub shutdown {
  my $self = shift;

  $self->is_shutdown(1);

  # flush any remaining messages that have pending receivers
  $self->flush;

  # send undef to any remaining receivers
  $_->send for @{ $self->waiters };
}

sub size {
  my $self = shift;
  return scalar @{ $self->buffer };
}

sub put {
  my $self = shift;
  push @{ $self->buffer }, @_;
  $self->flush;
  return $self->size;
}

sub get {
  my $self = shift;
  $self->async->recv;
}

sub async {
  my $self = shift;

  return shift @{ $self->buffer }
    if $self->is_shutdown;

  my $cv = AE::cv;
  push @{ $self->waiters }, $cv;

  $self->flush;

  return $cv;
}

sub flush {
  my $self = shift;
  while (@{ $self->waiters } && @{ $self->buffer }) {
    my $cv = shift @{ $self->waiters };
    $cv->send( shift @{ $self->buffer } );
  }
}

1;
