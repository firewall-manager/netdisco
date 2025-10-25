# Netdisco VLAN核心工作插件
# 此模块提供VLAN配置的核心功能，用于通过SNMP设置和更新网络设备的VLAN配置
package App::Netdisco::Worker::Plugin::Vlan::Core;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

# 注册早期阶段工作器 - 初始化VLAN设置前的准备工作
register_worker(
  {phase => 'early', driver => 'snmp'},  # 早期阶段，使用SNMP驱动
  sub {
    my ($job,    $workerconf) = @_;
    my ($device, $pn)         = map { $job->$_ } qw/device port/;  # 获取设备和端口信息

    # 使用读写社区字符串连接SNMP
    my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
      or return Status->defer("failed to connect to $device to update vlan/pvid");

    # 获取端口接口ID
    vars->{'iid'} = get_iid($snmp, vars->{'port'})
      or return Status->error("Failed to get port ID for [$pn] from $device");

    return Status->info("Vlan set can continue.");  # VLAN设置可以继续
  }
);

# 注册主阶段工作器 - 执行VLAN配置设置
register_worker(
  {phase => 'main', driver => 'snmp'},  # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;
    return unless defined vars->{'iid'};  # 确保接口ID已获取
    _action($job, 'pvid');                 # 设置PVID
    return _action($job, 'vlan');         # 设置VLAN
  }
);

# 执行VLAN配置操作的核心函数
sub _action {
  my ($job, $slot) = @_;  # 作业和配置槽位（pvid或vlan）
  my ($device, $pn, $data) = map { $job->$_ } qw/device port extra/;  # 获取设备、端口和数据

  # 构建SNMP方法名
  my $getter = "i_${slot}";    # 获取方法名
  my $setter = "set_i_${slot}";  # 设置方法名

  # 使用读写社区字符串连接SNMP
  my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
    or return Status->defer("failed to connect to $device to update $slot");

  # 执行SNMP设置操作
  my $rv = $snmp->$setter($data, vars->{'iid'});

  # 检查设置是否成功
  if (!defined $rv) {
    return Status->error(sprintf 'Failed to set [%s] %s to [%s] on $device: %s', $pn, $slot, $data,
      ($snmp->error || ''));
  }

  # 确认设置是否生效
  $snmp->clear_cache;  # 清除SNMP缓存
  my $state = ($snmp->$getter(vars->{'iid'}) || '');  # 获取当前状态
  if (ref {} ne ref $state or $state->{vars->{'iid'}} ne $data) {
    return Status->error("Verify of [$pn] $slot failed on $device");
  }

  # 更新Netdisco数据库
  vars->{'port'}->update({$slot => $data});

  return Status->done("Updated [$pn] $slot on [$device] to [$data]");
}

true;
