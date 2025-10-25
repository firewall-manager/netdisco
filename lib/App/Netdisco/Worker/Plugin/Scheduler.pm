package App::Netdisco::Worker::Plugin::Scheduler;

# 调度器工作器插件
# 提供定时任务调度功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

use JSON::PP ();

# 注册检查阶段工作器
# 验证调度器操作的可行性
register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;

  # 检查调度器数据
  return Status->error("Missing data of Scheduler entry")
    unless $job->extra;

  # 检查是否已初始化跳过列表
  return Status->defer("scheduler skipped: have not yet primed skiplist")
    unless schema(vars->{'tenant'})->resultset('DeviceSkip')
      ->search({
        backend => setting('workers')->{'BACKEND'},
        device  => '255.255.255.255',
      })->count();

  return Status->done('Scheduler is able to run');
});

# 注册主阶段工作器
# 执行定时任务调度
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  # 解析调度器配置
  my $coder = JSON::PP->new->utf8(0)->allow_nonref(1)->allow_unknown(1);
  my $sched = $coder->decode( $job->extra || {} );
  my $action = $sched->{action} || $sched->{label};

  # 检查调度器标签
  return Status->error("Missing label of Scheduler entry")
    unless $action;

  # 获取需要调度的设备列表
  my @walk = schema(vars->{'tenant'})->resultset('Virtual::WalkJobs')
    ->search(undef,{ bind => [
      $action, ('scheduled-'. $sched->{label}),
      setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'},
    ]})->get_column('ip')->all;

  # 插入调度任务到作业队列
  jq_insert([
    map {{
      device => $_,
      action => $action,
      port      => $sched->{port},
      subaction => $sched->{subaction},
      username => $job->username,
      userip   => $job->userip,
    }} (@walk)
  ]);

  return Status->done(sprintf 'Queued %s job for all devices', $action);
});

true;
