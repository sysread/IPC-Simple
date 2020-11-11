package IPC::Simple;
# ABSTRACT: simple, non-blocking IPC

=head1 SYNOPSIS

  use IPC::Simple;

  my $ssh = IPC::Simple->new(
    cmd  => 'ssh',
    args => [ $host ],
    eol  => "\n",
  );

  if ($ssh->launch) {
    $ssh->send('ls -lah');          # get directory listing
    $ssh->send('echo');             # signal our loop that the listing is done

    while (my $msg = $ssh->recv) {  # echo's output will be an empty string
      if ($msg->error) {            # I/O error
        croak $msg;
      }
      elsif ($msg->stderr) {        # output to STDERR
        warn $msg;
      }
      elsif ($msg->stdout) {        # output to STDOUT
        say $msg;
      }
    }

    $ssh->send('exit');             # terminate the connection
    $ssh->join;                     # wait for the process to terminate
  }

=head1 DESCRIPTION

Provides a simplified interface for managing and kibbitzing with a child
process.

=head1 METHODS

=head1 new

Creates a new C<IPC::Simple> process object. The process is not immediately
launched; see L</launch>.

=head2 constructor arguments

=over

=item cmd

The command to launch in a child process.

=item args

An array ref of arguments to C<cmd>.

=item eol

The end-of-line character to print at the end of each call to L</send>.
Defaults to C<"\n">.

=back

=head2 pid

Once launched, returns the pid of the child process.

=head2 exit_status

Once a child process exits, this is set to the exit status (C<$?>) of the child
process.

=head2 exit_code

Once a child process has terminated, this is set to the exit code of the child
process.

=head2 launch

Starts the child process. Returns true on success, croaks on failure to launch
the process.

=head2 terminate

Sends the child process a `SIGTERM`. Returns immediately. Use L</join> to wait
for the process to finish.

=head2 join

Blocks until the child process has exited.

=head2 send

Sends a string of text to the child process. The string will be appended with
the value of L</eol>.

=head2 recv

Waits for and returns the next line of output from the process, which may be
from C<STDOUT>, from C<STDERR>, or it could be an error message resulting from
an I/O error while communicating with the process (e.g. a C<SIGPIPE> or
abnormal termination).

Each message returned by C<recv> is an object overloaded so that it can be
treated as a string as well as providing the following methods:

=over

=item stdout

True when the message came from the child process' C<STDOUT>.

=item stderr

True when the message came from the child process' C<STDERR>.

=item error

True when the message is a sub-process communication error.

=back

=head1 DEBUGGING

C<IPC::Simple> will emit highly verbose messages to C<STDERR> if the
environment variable C<IPC_SIMPLE_DEBUG> is set to a true value.

=head1 MSWIN32 SUPPORT

Nope.

=cut

use strict;
use warnings;

use AnyEvent::Handle;
use AnyEvent;
use Carp;
use IPC::Open3 qw(open3);
use Moo;
use POSIX qw(:sys_wait_h);
use Symbol qw(gensym);
use Types::Standard -types;

use IPC::Simple::Channel;
use IPC::Simple::Message;
use IPC::Simple::Util;

use constant STATE_READY    => 0;
use constant STATE_RUNNING  => 1;
use constant STATE_STOPPING => 2;

has cmd =>
  is => 'ro',
  isa => Str,
  require => 1;

has args =>
  is => 'ro',
  isa => ArrayRef[Str],
  default => sub{ [] };

has eol =>
  is => 'ro',
  isa => Str,
  default => "\n",

has run_state =>
  is => 'rw',
  isa => Enum[ STATE_READY, STATE_RUNNING, STATE_STOPPING ],
  default => STATE_READY;

after run_state => sub{
  my $self = shift;
  debug('run state changed to %d', @_) if @_;
};

has pid =>
  is => 'rw',
  isa => Num,
  init_arg => undef;

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

has handle_in =>
  is => 'rw',
  isa => InstanceOf['AnyEvent::Handle'],
  init_arg => undef;

has handle_out =>
  is => 'rw',
  isa => InstanceOf['AnyEvent::Handle'],
  init_arg => undef;

has handle_err =>
  is => 'rw',
  isa => InstanceOf['AnyEvent::Handle'],
  init_arg => undef;

has exit_status =>
  is => 'rw',
  isa => Maybe[Int],
  init_arg => undef;

has exit_code =>
  is => 'rw',
  isa => Maybe[Int],
  init_arg => undef;

has messages =>
  is => 'rw',
  isa => InstanceOf['IPC::Simple::Channel'],
  init_arg => undef;

has _stdout =>
  is => 'ro',
  isa => Maybe[InstanceOf['IPC::Simple::Channel']],
  init_arg => undef,
  predicate => 1;

sub stdout {
  my $self = shift;
  my $key = '_' . IPC_STDOUT;
  $self->{$key} ||= IPC::Simple::Channel->new;
  return $self->{$key};
}

has _stderr =>
  is => 'ro',
  isa => Maybe[InstanceOf['IPC::Simple::Channel']],
  init_arg => undef,
  predicate => 1;

sub stderr {
  my $self = shift;
  my $key = '_' . IPC_STDERR;
  $self->{$key} ||= IPC::Simple::Channel->new;
  return $self->{$key};
}

has _errors =>
  is => 'ro',
  isa => Maybe[InstanceOf['IPC::Simple::Channel']],
  init_arg => undef,
  predicate => 1;

sub errors {
  my $self = shift;
  my $key = '_' . IPC_ERROR;
  $self->{$key} ||= IPC::Simple::Channel->new;
  return $self->{$key};
}

sub DEMOLISH {
  my $self = shift;
  $self->terminate;

  if ($self->pid) {
    waitpid $self->pid, 0;
  }
}

sub is_ready    { $_[0]->run_state == STATE_READY }
sub is_running  { $_[0]->run_state == STATE_RUNNING }
sub is_stopping { $_[0]->run_state == STATE_STOPPING }

sub launch {
  my $self = shift;

  if ($self->is_running) {
    croak 'already running';
  }

  if ($self->is_stopping) {
    croak 'process is terminating';
  }

  debug('launching: %s %s', $self->cmd, "@{$self->args}");

  my $pid = open3(my $in, my $out, my $err = gensym, $self->cmd, @{$self->args})
    or croak $!;

  debug('process launched with pid %d', $pid);

  $self->run_state(STATE_RUNNING);
  $self->exit_status(undef);
  $self->exit_code(undef);
  $self->pid($pid);
  $self->fh_in($in);
  $self->fh_out($out);
  $self->fh_err($err);
  $self->messages(IPC::Simple::Channel->new);
  $self->handle_err($self->_build_input_handle($err, IPC_STDERR));
  $self->handle_out($self->_build_input_handle($out, IPC_STDOUT));
  $self->handle_in($self->_build_output_handle($in));

  return 1;
}

sub _build_output_handle {
  my ($self, $fh) = @_;

  # set non-blocking
  AnyEvent::fh_unblock($fh);

  my $handle = AnyEvent::Handle->new(
    fh => $fh,
    on_error => sub{ $self->_on_error(IPC_STDIN, @_) },
  );

  return $handle;
}

sub _build_input_handle {
  my ($self, $fh, $type) = @_;

  # set non-blocking
  AnyEvent::fh_unblock($fh);

  my $handle = AnyEvent::Handle->new(
    fh       => $fh,
    on_eof   => sub{ $self->terminate },
    on_error => sub{ $self->_on_error($type, @_) },
    on_read  => sub{ $self->_on_read($type, @_) },
  );

  # push an initial read to prime the queue
  $self->_push_read($handle, $type);

  return $handle;
}

sub _on_error {
  my ($self, $type, $handle, $fatal, $msg) = @_;
  $self->_queue_message(IPC_ERROR, $msg);

  if ($fatal) {
    $self->terminate;
  }
}

sub _on_exit {
  my ($self, $status) = @_;
  $self->run_state(STATE_READY);
  $self->exit_status($status || 0);
  $self->exit_code($self->exit_status >> 8);

  debug('child (pid %s) exited with status %d (exit code: %d)',
    $self->pid || '(no pid)',
    $self->exit_status,
    $self->exit_code,
  );

  $self->messages->shutdown
    if $self->messages; # won't be set if launch failed early enough
}

sub _on_read {
  my ($self, $type, $handle) = @_;
  debug('read event type=%d', $type);
  $self->_push_read($handle, $type);
}

sub _push_read {
  my ($self, $handle, $type) = @_;
  $handle->push_read(line => $self->eol, sub{
    my ($handle, $line) = @_;
    chomp $line;
    $self->_queue_message($type, $line);
  });
}

sub _queue_message {
  my ($self, $type, $msg) = @_;
  my $channel = "_$type";
  debug('recv type=%s, msg="%s"', $type, $msg);

  if (exists $self->{$channel} && defined $self->{$channel}) {
    $self->{$channel}->put($msg);
  } else {
    $self->messages->put(
      IPC::Simple::Message->new(
        source  => $type,
        message => $msg,
      ),
    );
  }
}

sub terminate {
  my $self = shift;
  if ($self->is_running) {
    $self->run_state(STATE_STOPPING);
    debug('sending TERM to pid %d', $self->pid);
    kill 'TERM', $self->pid;

    $self->handle_in->push_shutdown;
    close $self->{fh_in};

    $self->handle_out->push_shutdown;
    close $self->{fh_out};

    $self->handle_err->push_shutdown;
    close $self->{fh_err};
  }
}

sub join {
  my $self = shift;

  return if $self->is_ready;

  debug('waiting for process to exit, pid %d', $self->pid);

  my $done = AnyEvent->condvar;

  my $timer; $timer = AnyEvent->timer(
    after => 0,
    interval => 0.01,
    cb => sub{
      # non-blocking waitpid returns 0 if the pid is still alive
      if (waitpid($self->pid, WNOHANG) != 0) {
        my $status = $?;

        # another waiter might have already called _on_exit
        unless ($self->is_ready) {
          $self->_on_exit($?);
        }

        $done->send;
      }
    },
  );

  $done->recv;
}

sub send {
  my ($self, $msg) = @_;
  debug('sending "%s"', $msg);
  $self->handle_in->push_write($msg . $self->eol);
  1;
}

sub recv {
  my ($self, $type) = @_;
  debug('waiting on message');
  $self->messages->get;
}

1;
