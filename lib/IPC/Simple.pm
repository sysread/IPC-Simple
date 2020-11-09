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

Sends a string of text to the child process. The string will be appended with a
single newline.

=head2 recv

Waits for and returns the next line of output from the process, which may be
from C<STDOUT>, from C<STDERR>, or it could be an error message resulting from
an I/O error while communicating with the process (e.g. a C<SIGPIPE> or
abnormal termination).

Each message returned by C<recv> is an object overloaded so that it can be
treated as a string as well as providing the following methods:

=head2 async

Schedules a callback for the next line of input to be received, returning
immediately.

  $proc->async(sub{
    my $msg = shift;

    if ($msg->stdout) {
      ...
    }
  });

This is done with L<AnyEvent/CONDITION-VARIABLES>, so the same caveats about
races and dead locks apply. It is up to the caller to manage their event loop.

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

BEGIN{
  extends 'Exporter';

  our @EXPORT = qw(
    IPC_STDOUT
    IPC_STDERR
    IPC_ERROR
  );
}

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
  default => sub{ $/ };

has run_state =>
  is => 'rw',
  isa => Enum[ STATE_READY, STATE_RUNNING, STATE_STOPPING ],
  default => STATE_READY;

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
  init_arg => undef,
  handles => {
    recv => 'get',
  };

sub DEMOLISH {
  my $self = shift;
  $self->terminate;
  $self->join;
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

  my $pid = open3(
    my $in,
    my $out,
    my $err = gensym,
    $self->cmd,
    @{$self->args},
  ) or croak $!;

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

$self->{debug_proc} = AnyEvent->timer(after => 0.1, interval => 0.5, cb => sub{
  my $waitpid = waitpid $self->pid, WNOHANG;
  debug('child process check; waitpid=%s, status=%s', $waitpid, $?);

  if ($waitpid != 0) {
    delete $self->{debug_proc};
  }
});

  return 1;
}

sub _build_output_handle {
  my ($self, $fh) = @_;

  # set non-blocking
  AnyEvent::fh_unblock($fh);

  my $handle = AnyEvent::Handle->new(
    fh       => $fh,
    on_error => sub{ $self->_on_error(0, @_) },
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

  # queue an initial read to ensure the event loop is watching for reads
  $self->_push_read($handle, $type);

  return $handle;
}

sub _on_error {
  my ($self, $type, $handle, $fatal, $msg) = @_;
  debug('recv error type=%d, msg="%s"', $type, $msg);

  $self->messages->put(
    IPC::Simple::Message->new(
      source  => IPC_ERROR,
      message => $msg,
    ),
  );

  $self->terminate if $fatal;
}

sub _on_exit {
  my ($self, $status) = @_;
  $self->run_state(STATE_READY);
  $self->exit_status($status || 0);
  $self->exit_code($self->exit_status >> 8);
  $self->messages->shutdown;
  debug('child (pid %d) exited with status %d (exit code: %d)', $self->pid, $self->exit_status, $self->exit_code);
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
    debug('recv type=%d, msg="%s"', $type, $line);

    $self->messages->put(
      IPC::Simple::Message->new(
        source  => $type,
        message => $line,
      ),
    );
  });
}

sub terminate {
  my $self = shift;
  if ($self->is_running) {
    $self->run_state(STATE_STOPPING);

    if (AnyEvent::WIN32) {
      debug('sending KILL to pid %d', $self->pid);
      kill 'KILL', $self->pid;
    } else {
      debug('sending TERM to pid %d', $self->pid);
      kill 'TERM', $self->pid;
    }
  }
}

sub join {
  my $self = shift;

  if ($self->is_ready) {
    return;
  }

  my $done = AnyEvent->condvar;
  my $status;

  my $check; $check = AnyEvent->timer(interval => 0.1, cb => sub{
    my $waitpid = waitpid $self->pid, WNOHANG;

    if ($waitpid != 0) {
      $status = $?;
      debug('child process complete; waitpid=%s, status=%s', $waitpid, $status);
      $done->send;
      undef $check;
    }
  });

  debug('waiting for process to exit, pid %d', $self->pid);

  $done->recv;
  $self->_on_exit($status);
}

sub send {
  my ($self, $msg) = @_;
  $self->handle_in->push_write($msg . $self->eol);
  debug('sent "%s"', $msg);
}

around recv => sub{
  my $orig = shift;
  my $self = shift;
  debug('waiting on message');
  $self->$orig();
};

sub async {
  my ($self, $cb) = @_;
  my $cv = $self->messages->async;
  $cv->cb(sub{ $cb->( $cv->recv ) });
  return;
}

after run_state => sub{
  my $self = shift;
  debug('run state changed to %d', @_) if @_;
};

1;
