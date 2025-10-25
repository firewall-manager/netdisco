package App::Netdisco::Worker::Plugin::Macsuck;

# MAC地址收集工作器插件
# 提供MAC地址表信息收集功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_macsuckable_now';

# 注册检查阶段工作器
# 验证MAC地址收集操作的可行性
register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # 检查设备参数
  return Status->error('macsuck failed: unable to interpret device param')
    unless defined $device;

  # 检查设备是否已发现
  return Status->error("macsuck skipped: $device not yet discovered")
    unless $device->in_storage;

  # 处理离线模式或MAC收集能力
  if ($job->port or $job->extra) {
      $job->is_offline(true);
      debug 'macsuck offline: will update from CLI or API';
  }
  else {
      return Status->info("macsuck skipped: $device is not macsuckable")
        unless is_macsuckable_now($device);
  }

  # 支持钩子功能
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # 为隐私考虑

  return Status->done('Macsuck is able to run.');
});

true;
