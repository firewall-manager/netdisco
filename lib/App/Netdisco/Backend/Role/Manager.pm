package App::Netdisco::Backend::Role::Manager;

# 管理器角色模块
# 提供作业队列管理和分发功能

use Dancer qw/:moose :syntax :script/;

use List::Util 'sum';
use Proc::ProcessTable;
use App::Netdisco::Util::MCE;

use App::Netdisco::Backend::Job;
use App::Netdisco::JobQueue qw/jq_locked jq_getsome jq_lock jq_warm_thrusters/;

use Role::Tiny;
use namespace::clean;

# 工作进程开始
# 初始化管理器工作进程，预热作业队列并重新排队本地作业
sub worker_begin {
  my $self = shift;
  my $wid  = $self->wid;

  return debug "mgr ($wid): no need for manager... skip begin" if setting('workers')->{'no_manager'};

  debug "entering Manager ($wid) worker_begin()";

  # 作业队列初始化
  # 昂贵部分已移至primeskiplist作业
  jq_warm_thrusters;

  # 排队一个作业以重建设备操作跳过列表
  $self->{queue}->enqueuep(200, App::Netdisco::Backend::Job->new({job => 0, action => 'primeskiplist'}));

  # 本地重新排队作业
  debug "mgr ($wid): searching for jobs booked to this processing node";
  my @jobs = jq_locked;

  if (scalar @jobs) {
    info sprintf "mgr (%s): found %s jobs booked to this processing node", $wid, scalar @jobs;
    $self->{queue}->enqueuep(100, @jobs);
  }
}

# 为每个作业创建"签名"以便检查重复...
# 由于作业队列和管理器的分布式特性，这种情况时有发生
# 在这里跳过比在jq_lock()中跳过对数据库更友好
my $memoize = sub {
  no warnings 'uninitialized';
  my $job = shift;
  return join chr(28), map { $job->{$_} } (qw/action port subaction/, ($job->{device_key} ? 'device_key' : 'device'));
};

# 工作进程主体
# 管理器的主要工作循环，负责从队列获取作业并分发给工作进程
sub worker_body {
  my $self = shift;
  my $wid  = $self->wid;

  if (setting('workers')->{'no_manager'}) {
    prctl sprintf 'nd2: #%s mgr: inactive', $wid;
    return debug "mgr ($wid): no need for manager... quitting";
  }

  while (1) {
    prctl sprintf 'nd2: #%s mgr: gathering', $wid;
    my $num_slots = 0;
    my %seen_job  = ();

    # 这确实存在竞态条件，但我们保护的作业
    # 可能是长时间运行的
    my $t = Proc::ProcessTable->new('enable_ttys' => 0);

    $num_slots = parse_max_workers(setting('workers')->{tasks}) - $self->{queue}->pending();
    debug "mgr ($wid): getting potential jobs for $num_slots workers" if not $ENV{ND2_SINGLE_WORKER};

  JOB: foreach my $job (jq_getsome($num_slots)) {
      my $display_name = $job->action . ' ' . ($job->device || '');

      if ($seen_job{$memoize->($job)}++) {
        debug "mgr ($wid): duplicate queue job detected: $display_name";
        next JOB;
      }

      # 1392检查是否有相同的作业已在运行
      if ($job->device) {
        foreach my $p (@{$t->table}) {
          if ($p->cmndline and $p->cmndline =~ m/nd2: #\d+ poll: #\d+: ${display_name}/) {
            debug "mgr ($wid): duplicate running job detected: $display_name";
            next JOB;
          }
        }
      }

      # 标记作业为运行中
      jq_lock($job) or next JOB;
      info sprintf "mgr (%s): job %s booked out for this processing node", $wid, $job->id;

      # 将作业复制到本地队列
      $self->{queue}->enqueuep($job->job_priority, $job);
    }

    #if (scalar grep {$_ > 1} values %seen_job) {
    #  debug 'WARNING: saw duplicate jobs after getsome()';
    #  use DDP; debug p %seen_job;
    #}

    debug "mgr ($wid): sleeping now..." if not $ENV{ND2_SINGLE_WORKER};
    prctl sprintf 'nd2: #%s mgr: idle', $wid;
    sleep(setting('workers')->{sleep_time} || 1);
  }
}

1;
