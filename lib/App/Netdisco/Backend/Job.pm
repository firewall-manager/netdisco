package App::Netdisco::Backend::Job;

# 后端作业类
# 提供作业对象的基本属性和状态管理功能

use Dancer qw/:moose :syntax !error/;
use aliased 'App::Netdisco::Worker::Status';

use Moo;
use Term::ANSIColor qw(:constants :constants256);
use namespace::clean;

# 定义作业的基本属性
# 包括作业ID、时间戳、设备信息、动作、状态等
foreach my $slot (qw/
      job
      entered
      started
      finished
      device
      port
      action
      only_namespace
      subaction
      status
      username
      userip
      log
      device_key
      backend
      job_priority
      is_cancelled
      is_offline

      _current_phase
      _last_namespace
      _last_priority
    /) {

  has $slot => (
    is => 'rw',
  );
}

# 状态列表，用于存储作业执行过程中的状态信息
has '_statuslist' => (
  is => 'rw',
  default => sub { [] },
);

# 构建器方法
# 初始化作业对象，处理动作名称空间和子动作
sub BUILD {
  my ($job, $args) = @_;

  # 处理动作名称空间格式 "action::namespace"
  if ($job->action =~ m/^(\w+)::(\w+)$/i) {
    $job->action($1);
    $job->only_namespace($2);
  }

  # 确保子动作为空字符串而不是未定义
  if (!defined $job->subaction) {
    $job->subaction('');
  }
}

=head1 METHODS

=head2 display_name

An attempt to make a meaningful written statement about the job.

=cut

# 显示名称
# 生成作业的有意义描述
sub display_name {
  my $job = shift;
  return join ' ',
    $job->action,
    ($job->device || ''),
    ($job->port || '');
}

=head2 cancel

Log a status and prevent other stages from running.

=cut

# 取消作业
# 记录状态并防止其他阶段运行
sub cancel {
  my ($job, $msg) = @_;
  $msg ||= 'unknown reason for cancelled job';
  $job->is_cancelled(true);
  return Status->error($msg);
}

=head2 best_status

Find the best status so far. The process is to track back from the last worker
and find the highest scoring status, skipping the check phase.

=cut

# 最佳状态
# 查找到目前为止的最佳状态，从最后一个工作进程开始追踪
# 找到最高分状态，跳过检查阶段
sub best_status {
  my $job = shift;
  my $cur_level = 0;
  my $cur_status = '';

  foreach my $status (reverse @{ $job->_statuslist }) {
    next if $status->phase
      and $status->phase !~ m/^(?:early|main|store|late)$/;

    if ($status->level >= $cur_level) {
      $cur_level = $status->level;
      $cur_status = $status->status;
    }
  }

  return $cur_status;
}

=head2 finalise_status

Find the best status and log it into the job's C<status> and C<log> slots.

=cut

# 最终化状态
# 找到最佳状态并将其记录到作业的status和log槽中
sub finalise_status {
  my $job = shift;
  # use DDP; p $job->_statuslist;

  # 回退状态
  $job->status('error');
  $job->log('failed to report from any worker!');

  my $max_level = 0;

  foreach my $status (reverse @{ $job->_statuslist }) {
    next if $status->phase
      and $status->phase !~ m/^(?:check|early|main|user|store|late)$/;

    # 检查阶段的done()不应该是动作的done()
    next if $status->phase eq 'check' and $status->is_ok;

    # 对于done()我们想要最新的日志消息
    # 对于error()（和其他）我们想要最早的日志消息

    if (($max_level != Status->done()->level and $status->level >= $max_level)
        or ($status->level > $max_level)) {

      $job->status( $status->status );
      $job->log( $status->log );
      $max_level = $status->level;
    }
  }
}

=head2 check_passed

Returns true if at least one worker during the C<check> phase flagged status
C<done>.

=cut

# 检查通过
# 如果在check阶段至少有一个工作进程标记状态为done则返回true
sub check_passed {
  my $job = shift;
  return true if 0 == scalar @{ $job->_statuslist };

  foreach my $status (@{ $job->_statuslist }) {
    return true if
      (($status->phase eq 'check') and $status->is_ok);
  }
  return false;
}

=head2 namespace_passed( \%workerconf )

Returns true when, for the namespace specified in the given configuration, a
worker of a higher priority level has already succeeded.

=cut

# 名称空间通过
# 当在给定配置中指定的名称空间，更高优先级的工作进程已经成功时返回true
sub namespace_passed {
  my ($job, $workerconf) = @_;

  if ($job->_last_namespace) {
    foreach my $status (@{ $job->_statuslist }) {
      next unless ($status->phase eq $workerconf->{phase})
              and ($workerconf->{namespace} eq $job->_last_namespace)
              and ($workerconf->{priority} < $job->_last_priority);
      return true if $status->is_ok;
    }
  }

  $job->_last_namespace( $workerconf->{namespace} );
  $job->_last_priority( $workerconf->{priority} );
  return false;
}

=head2 enter_phase( $phase )

Pass the name of the phase being entered.

=cut

# 进入阶段
# 传递正在进入的阶段名称
sub enter_phase {
  my ($job, $phase) = @_;

  $job->_current_phase( $phase );
  debug BRIGHT_CYAN, "//// ", uc($phase), ' \\\\\\\\ ', GREY10, 'phase', RESET;

  $job->_last_namespace( undef );
  $job->_last_priority( undef );
}

=head2 add_status

Passed an L<App::Netdisco::Worker::Status> will add it to this job's internal
status cache. Phase slot of the Status will be set to the current phase.

=cut

# 添加状态
# 传递App::Netdisco::Worker::Status对象，将其添加到此作业的内部状态缓存
# Status的Phase槽将设置为当前阶段
sub add_status {
  my ($job, $status) = @_;
  return unless ref $status eq 'App::Netdisco::Worker::Status';
  $status->phase( $job->_current_phase || '' );
  push @{ $job->_statuslist }, $status;
  if ($status->log) {
      debug GREEN, "\N{LEFTWARDS BLACK ARROW} ", BRIGHT_GREEN, '(', $status->status, ') ', GREEN, $status->log, RESET;
  }
}

=head1 ADDITIONAL COLUMNS

Columns which exist in this class but are not in
L<App::Netdisco::DB::Result::Admin> class.


=head2 id

Alias for the C<job> column.

=cut

# ID别名
# job列的别名
sub id { (shift)->job }

# 额外信息别名
# subaction列的别名
sub extra { (shift)->subaction }

true;
