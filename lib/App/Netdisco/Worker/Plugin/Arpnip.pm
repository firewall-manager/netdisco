package App::Netdisco::Worker::Plugin::Arpnip;

# ARP NIP工作器插件
# 提供ARP表信息收集功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'is_arpnipable_now';

# 注册检查阶段工作器
# 验证ARP NIP操作的可行性
register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my $device = $job->device;

  # 检查设备参数
  return Status->error('arpnip failed: unable to interpret device param')
    unless defined $device;

  # 检查设备是否已发现
  return Status->error("arpnip skipped: $device not yet discovered")
    unless $device->in_storage;

  # 检查离线模式或ARP能力
  if ($job->port or $job->extra) {
      $job->is_offline(true);
      debug 'arpnip offline: will update from CLI or API';
  }
  else {
      return Status->info("arpnip skipped: $device is not arpnipable")
        unless is_arpnipable_now($device);
  }

  # 支持钩子功能
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # 为隐私考虑

  return Status->done('arpnip is able to run');
});

true;
