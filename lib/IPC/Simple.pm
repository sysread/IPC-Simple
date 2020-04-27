package IPC::Simple;
# ABSTRACT: easy, non-blocking IPC

use strict;
use warnings;

use AnyEvent::Handle;
use AnyEvent;
use Carp;
use Fcntl;
use IPC::Open3 qw(open3);
use Moo;
use POSIX qw(:sys_wait_h);
use Symbol qw(gensym);
use Types::Standard -types;
use IPC::Simple::Channel;

use constant IPC_STDOUT => 1;
use constant IPC_STDERR => 2;
use constant IPC_ERROR  => 3;

use constant STATE_READY    => 0;
use constant STATE_RUNNING  => 1;
use constant STATE_STOPPING => 2;

BEGIN{
  extends 'Exporter';

  our @EXPORT = qw(
    IPC_STDOUT
    IPC_STDERR
    IPC_ERROR
  );
}

has cmd =>
  is => 'ro',
  isa => Str,
  require => 1;

has args =>
  is => 'ro',
  isa => ArrayRef[Str],
  default => sub{ [] };

has run_state =>
  is => 'rw',
  isa => Enum[ STATE_READY, STATE_RUNNING, STATE_STOPPING ],
  default => STATE_READY;

has pid =>
  is => 'rw',
  isa => Num,
  init_arg => undef;

has proc_monitor =>
  is => 'rw',
  init_arg => undef,
  clearer => 1;

has fh_in =>
  is => 'rw',
  isa => FileHandle,
  init_arg => undef;

has fh_out =>
  is => 'rw',
  isa => FileHandle,
  init_arg => undef;

has fh_err =>
  is => 'rw',
  isa => FileHandle,
  init_arg => undef;

has handle_out =>
  is => 'rw',
  isa => InstanceOf['AnyEvent::Handle'],
  init_arg => undef;

has handle_err =>
  is => 'rw',
  isa => InstanceOf['AnyEvent::Handle'],
  init_arg => undef;

has cv_exited =>
  is => 'rw',
  isa => InstanceOf['AnyEvent::CondVar'],
  init_arg => undef;

has exit_status =>
  is => 'rw',
  isa => Maybe[Int],
  init_arg => undef;

has messages =>
  is => 'rw',
  isa => InstanceOf['IPC::Simple::Channel'],
  init_arg => undef;

sub DEMOLISH {
  my $self = shift;
  $self->terminate;
  $self->join;
}

sub debug {
  if ($ENV{IPC_SIMPLE_DEBUG}) {
    my $msg = sprintf shift, @_;
    warn "<IPC::Simple> $msg\n";
  }
}

after run_state => sub{
  my $self = shift;
  debug('run state changed to %d', @_) if @_;
};

sub is_ready    { $_[0]->run_state == STATE_READY }
sub is_running  { $_[0]->run_state == STATE_RUNNING }
sub is_stopping { $_[0]->run_state == STATE_STOPPING }

sub exit_code {
  my $self = shift;
  return unless defined $self->exit_status;
  return $self->exit_status >> 8;
}

sub launch {
  my $self = shift;

  if ($self->is_running) {
    croak 'already running';
  }

  if ($self->is_stopping) {
    croak 'process is terminating';
  }

  debug('launching: %s %s', $self->cmd, "@{$self->args}");

  my $pid = open3(
    my $in,
    my $out,
    my $err = gensym,
    $self->cmd,
    @{$self->args},
  ) or croak $!;

  my $cv = AE::cv;

  $self->run_state(STATE_RUNNING);
  $self->cv_exited($cv);
  $self->pid($pid);
  $self->fh_in($in);
  $self->fh_out($out);
  $self->fh_err($err);
  $self->messages(IPC::Simple::Channel->new);
  $self->handle_err($self->_build_handle($err, IPC_STDERR));
  $self->handle_out($self->_build_handle($out, IPC_STDOUT));

  $self->proc_monitor(
    AE::child($pid, sub{
      my ($pid, $status) = @_;
      debug('child (pid %d) exited with status %d (exit code: %d)', $pid, $status, $status >> 8);
      $self->run_state(STATE_READY);
      $self->exit_status($status);
      $self->messages->shutdown;
      $cv->send($status);
      $self->clear_proc_monitor;
    })
  );

  return 1;
}

sub _build_handle {
  my ($self, $fh, $type) = @_;

  # set non-blocking
  my $flags = fcntl $fh, F_GETFL, 0;
  fcntl $fh, F_SETFL, $flags | O_NONBLOCK;

  return AnyEvent::Handle->new(
    fh => $fh,
    on_eof => sub{ $self->terminate },

    on_error => sub{
      my ($handle, $fatal, $msg) = @_;
      debug('recv error type=%d, msg="%s"', $type, $msg);
      $self->messages->put([$msg, IPC_ERROR]);
      $self->terminate if $fatal;
    },

    on_read => sub{
      my ($handle) = @_;
      debug('read event type=%d', $type);

      $handle->push_read(line => sub{
        my ($handle, $line) = @_;
        chomp $line;
        debug('recv type=%d, msg="%s"', $type, $line);
        $self->messages->put([$line, $type]);
      });
    },
  );
}

sub terminate {
  my $self = shift;
  if ($self->is_running) {
    debug('sending TERM to pid %d', $self->pid);
    $self->run_state(STATE_STOPPING);
    kill 'TERM', $self->pid;
  }
}

sub join {
  my $self = shift;
  if ($self->cv_exited) {
    debug('waiting for process to exit, pid %d', $self->pid);
    $self->cv_exited->recv;
  }
}

sub send {
  my ($self, $msg) = @_;
  my $fh = $self->fh_in;
  local $| = 1;
  print $fh "$msg\n";
}

sub recv {
  my $self = shift;
  return $self->messages->get;
}

1;
