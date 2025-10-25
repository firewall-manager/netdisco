package App::Netdisco::Worker::Plugin::Nbtstat;

# NetBIOS统计工作器插件
# 提供NetBIOS统计信息收集功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_macsuckable';

# 注册检查阶段工作器
# 验证NetBIOS统计操作的可行性
register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;

  # 检查设备参数
  return Status->error('nbtstat failed: unable to interpret device param')
    unless defined $job->device;

  # 检查设备是否支持MAC地址收集
  return Status->info(sprintf 'nbtstat skipped: %s is not macsuckable', $job->device->ip)
    unless is_macsuckable($job->device);

  return Status->done('Nbtstat is able to run.');
});

true;
