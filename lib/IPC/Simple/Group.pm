package IPC::Simple::Group;

use strict;
use warnings;

use Carp;
use IPC::Simple::Channel qw();

sub new {
  my $class = shift;

  my $self = bless{
    members  => {},
    messages => IPC::Simple::Channel->new,
  }, $class;

  $self->add(@_);

  return $self;
}

sub add {
  my $self = shift;

  for (@_) {
    croak 'processes must be grouped *before* launching them'
      unless $_->is_ready;

    croak 'processes must be named to be grouped'
      unless $_->name;

    croak 'processes with a recv_cb may not be grouped'
      if $_->{cb};

    croak 'processes with a term_cb may not be grouped'
      if $_->{term_cb};
  }

  for (@_) {
    $self->{members}{ $_->{name} } = $_;
    $_->{recv_cb} = sub{ $self->{messages}->put( $_[0] ) };
    $_->{term_cb} = sub{ $self->drop( $_[0] ) };
  }
}

sub drop {
  my $self = shift;

  delete $self->{members}{ $_->{name} }
    for @_;

  unless (%{ $self->{members} }) {
    $self->{messages}->shutdown;
  }
}

sub members {
  my $self = shift;
  return values %{ $self->{members} };
}

sub launch {
  my $self = shift;
  $_->launch for $self->members;
}

sub terminate {
  my $self = shift;
  $_->terminate for $self->members;
}

sub join {
  my $self = shift;
  $_->join for $self->members;
}

sub recv {
  my $self = shift;
  $self->{messages}->recv;
}

1;
