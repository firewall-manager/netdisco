package App::Netdisco::Worker::Runner;

# 工作器运行器
# 提供工作器的执行和调度功能

use Dancer qw/:moose :syntax/;
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Util::CustomFields;
use App::Netdisco::Transport::Python ();
use App::Netdisco::Util::Device 'get_device';
use App::Netdisco::Util::Permission qw/acl_matches acl_matches_only/;
use aliased 'App::Netdisco::Worker::Status';

use Try::Tiny;
use Time::HiRes ();
use Module::Load ();
use Scope::Guard 'guard';
use Storable 'dclone';
use Sys::SigAction 'timeout_call';

use Moo::Role;
use namespace::clean;

with 'App::Netdisco::Worker::Loader';
has 'job' => ( is => 'rw' );

# 运行通过插件加载的工作器的混合代码
sub run {
  my ($self, $job) = @_;

  die 'cannot reuse a worker' if $self->job;
  die 'bad job to run()'
    unless ref $job eq 'App::Netdisco::Backend::Job';

  $self->job($job);
  $job->device( get_device($job->device) )
    unless scalar grep {$job->action eq $_} @{ setting('job_targets_prefix') };
  $self->load_workers();

  # 退出时清理并完成任务状态
  my $statusguard = guard {
    if (var('live_python')) {
      try { App::Netdisco::Transport::Python->runner->finish };
      try { App::Netdisco::Transport::Python->runner->kill_kill };
      try { unlink App::Netdisco::Transport::Python->context->filename };
    }
    $job->finalise_status;
  };

  my @newuserconf = ();
  my @userconf = @{ dclone (setting('device_auth') || []) };

  # 通过only/no减少device_auth
  if (ref $job->device) {
    foreach my $stanza (@userconf) {
      my $no   = (exists $stanza->{no}   ? $stanza->{no}   : undef);
      my $only = (exists $stanza->{only} ? $stanza->{only} : undef);

      next if $no and acl_matches($job->device, $no);
      next if $only and not acl_matches_only($job->device, $only);

      push @newuserconf, dclone $stanza;
    }

    # 每个设备动作但没有设备凭据可用
    return $job->add_status( Status->defer('deferred job with no device creds') )
      if 0 == scalar @newuserconf && $self->transport_required;
  }

  # 备份和恢复device_auth
  my $configguard = guard { set(device_auth => \@userconf) };
  set(device_auth => \@newuserconf);

  # 运行器子程序
  my $runner = sub {
    my ($self, $job) = @_;
    # 如果我们在测试，回滚所有内容
    my $txn_guard = $ENV{ND2_DB_ROLLBACK}
      ? schema('netdisco')->storage->txn_scope_guard : undef;

    # 运行检查阶段，如果有工作器，则必须有一个成功
    $self->run_workers('workers_check');

    # 运行其他阶段
    if ($job->check_passed or $ENV{ND2_WORKER_ROLL_CALL}) {
      $self->run_workers("workers_${_}") for qw/early main user store late/;
    }
  };

  my $maxtime = ((defined setting($job->action .'_timeout'))
    ? setting($job->action .'_timeout') : setting('workers')->{'timeout'});

  # 如果设备是新的且需要认证遍历，为超时添加一些余量
  $maxtime += (40 * scalar @newuserconf) if ref $job->device and not $job->device->in_storage;

  if ($maxtime) {
    debug sprintf '%s: running with timeout %ss', $job->action, $maxtime;
    if (timeout_call($maxtime, $runner, ($self, $job))) {
      debug sprintf '%s: timed out!', $job->action;
      $job->add_status( Status->error("job timed out after $maxtime sec") );
    }
  }
  else {
    debug sprintf '%s: running with no timeout', $job->action;
    $runner->($self, $job);
  }
}

# 运行工作器方法
# 执行指定集合中的工作器
sub run_workers {
  my $self = shift;
  my $job = $self->job or die error 'no job in worker job slot';

  my $set = shift
    or return $job->add_status( Status->error('missing set param') );
  return unless ref [] eq ref $self->$set and 0 < scalar @{ $self->$set };

  (my $phase = $set) =~ s/^workers_//;
  $job->enter_phase($phase);

  # 执行每个工作器
  foreach my $worker (@{ $self->$set }) {
    try { $job->add_status( $worker->($job) ) }
    catch {
      debug "-> $_" if $_;
      $job->add_status( Status->error($_) );
    };
  }
}

true;
