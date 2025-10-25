package App::Netdisco::Worker::Plugin::Delete;

# 设备删除工作器插件
# 提供设备删除功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device 'delete_device';

# 注册检查阶段工作器
# 验证设备删除操作的可行性
register_worker({ phase => 'check' }, sub {
  return Status->error('Missing device (-d).')
    unless shift->device;
  return Status->done('Delete is able to run');
});

# 注册主阶段工作器
# 执行设备删除操作
register_worker({ phase => 'main' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port) = map {$job->$_} qw/device port/;

  # 检查设备参数
  return Status->error('Missing device (-d).')
    unless defined $device;

  # 检查设备是否存在于存储中
  if (! $device->in_storage) {
      return Status->error(sprintf "unknown device: %s.", $device);
  }

  # 支持钩子功能
  vars->{'hook_data'} = { $device->get_columns };
  delete vars->{'hook_data'}->{'snmp_comm'}; # 为隐私考虑

  # 执行设备删除
  $port = ($port ? 1 : 0);
  my $happy = delete_device($device, $port);

  if ($happy) {
      return Status->done("Deleted device: $device")
  }
  else {
      return Status->error("Failed to delete device: $device")
  }
});

true;
