package App::Netdisco::Worker::Plugin::Discover;

# 设备发现工作器插件
# 提供单个设备发现功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_discoverable_now';
use Time::HiRes 'gettimeofday';

# 注册检查阶段工作器
# 验证设备发现操作的可行性
register_worker(
  {phase => 'check'},
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # 检查设备参数
    return Status->error('discover failed: unable to interpret device param') unless defined $device;

    # 检查设备IP参数
    return Status->error("discover failed: no device param (need -d ?)") if $device->ip eq '0.0.0.0';

    # 检查设备是否可发现
    return Status->info("discover skipped: $device is not discoverable") unless is_discoverable_now($device);

    # 设置时间戳，用于记录更新记录
    # 使用相同的时间戳值，可以在最后添加作业来选择和处理更新的集合
    vars->{'timestamp'}
      = ($job->is_offline and $job->entered)
      ? (schema('netdisco')->storage->dbh->quote($job->entered) . '::timestamp')
      : 'to_timestamp(' . (join '.', gettimeofday) . ')::timestamp';

    return Status->done('Discover is able to run.');
  }
);

true;
