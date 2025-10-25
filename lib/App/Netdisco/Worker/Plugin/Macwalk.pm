package App::Netdisco::Worker::Plugin::Macwalk;

# MAC地址遍历工作器插件
# 提供批量MAC地址收集任务调度功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';

# 注册检查阶段工作器
# 验证MAC地址遍历操作的准备状态
register_worker({ phase => 'check' }, sub {
  # 检查是否已初始化跳过列表
  return Status->defer("macwalk skipped: have not yet primed skiplist")
    unless schema(vars->{'tenant'})->resultset('DeviceSkip')
      ->search({
        backend => setting('workers')->{'BACKEND'},
        device  => '255.255.255.255',
      })->count();

  return Status->done('Macwalk is able to run');
});

# 注册主阶段工作器
# 批量调度MAC地址收集任务
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;

  # 获取需要遍历的设备列表
  my @walk = schema(vars->{'tenant'})->resultset('Virtual::WalkJobs')
    ->search(undef,{ bind => [
      'macsuck', 'macsuck',
      setting('workers')->{'max_deferrals'},
      setting('workers')->{'retry_after'},
    ]})->get_column('ip')->all;

  # 插入MAC地址收集任务到作业队列
  jq_insert([
    map {{
      device => $_,
      action => 'macsuck',
      username => $job->username,
      userip => $job->userip,
    }} (@walk)
  ]);

  return Status->done('Queued macsuck job for all devices');
});

true;
