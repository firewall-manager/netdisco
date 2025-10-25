package App::Netdisco::Worker::Plugin::Power;

# 电源控制工作器插件
# 提供网络端口PoE电源控制功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

# 注册检查阶段工作器
# 验证PoE电源控制操作的可行性
register_worker({ phase => 'check' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $port) = map {$job->$_} qw/device port/;

  # 检查设备参数
  return Status->error('Power failed: unable to interpret device param')
    unless defined $device;

  # 检查设备是否已发现
  return Status->error("Power skipped: $device not yet discovered")
    unless $device->in_storage;

  # 检查端口参数
  return Status->error('Missing port (-p).') unless defined $job->port;

  # 获取端口对象
  vars->{'port'} = get_port($device, $port)
    or return Status->error("Unknown port name [$port] on device $device");

  # 检查状态参数
  return Status->error('Missing status (-e).') unless defined $job->subaction;

  # 同步端口控制角色并检查权限
  sync_portctl_roles();
  return Status->error("Permission denied to alter power status")
    unless port_acl_service(vars->{'port'}, $device, $job->username);

  # 检查端口是否支持PoE
  return Status->error("No PoE service on port [$port] on device $device")
    unless vars->{'port'}->power;

  return Status->done('Power is able to run');
});

# 注册主阶段工作器
# 执行PoE电源控制操作
register_worker({ phase => 'main', driver => 'snmp' }, sub {
  my ($job, $workerconf) = @_;
  my ($device, $pn) = map {$job->$_} qw/device port/;

  # 处理数据格式
  (my $data = $job->subaction) =~ s/-\w+//; # 移除-other后缀
  $data = 'true'  if $data =~ m/^(on|yes|up)$/;
  $data = 'false' if $data =~ m/^(off|no|down)$/;

  # 使用读写社区字符串进行SNMP连接
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to set power");

  # 获取电源ID
  my $powerid = get_powerid($snmp, vars->{'port'})
    or return Status->error("failed to get power ID for [$pn] from $device");

  # 设置PoE端口管理状态
  my $rv = $snmp->set_peth_port_admin($data, $powerid);

  if (!defined $rv) {
      return Status->error(sprintf 'failed to set [%s] power to [%s] on [%s]: %s',
                    $pn, $data, $device, ($snmp->error || ''));
  }

  # 确认设置成功
  $snmp->clear_cache;
  my $state = ($snmp->peth_port_admin($powerid) || '');
  if (ref {} ne ref $state or $state->{$powerid} ne $data) {
      return Status->error("Verify of [$pn] power failed on $device");
  }

  # 更新Netdisco数据库
  vars->{'port'}->power->update({
    admin => $data,
    status => ($data eq 'false' ? 'disabled' : 'searching'),
  });

  return Status->done("Updated [$pn] power status on $device to [$data]");
});

true;
