package App::Netdisco::Worker::Plugin::PortName;

# 端口名称工作器插件
# 提供网络端口名称/别名设置功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP;
use App::Netdisco::Util::Port ':all';

# 注册检查阶段工作器
# 验证端口名称设置操作的可行性
register_worker(
  {phase => 'check'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $port, $data) = map { $job->$_ } qw/device port extra/;

    # 检查设备参数
    return Status->error('PortName failed: unable to interpret device param') unless defined $device;

    # 检查设备是否已发现
    return Status->error("PortName skipped: $device not yet discovered") unless $device->in_storage;

    # 检查端口参数
    return Status->error('Missing port (-p).') unless defined $job->port;

    # 获取端口对象
    vars->{'port'} = get_port($device, $port) or return Status->error("Unknown port name [$port] on device $device");

    # 检查名称参数
    return Status->error('Missing name (-e).') unless defined $job->subaction;

    # 同步端口控制角色并检查权限
    sync_portctl_roles();
    return Status->error("Permission denied to change port name")
      unless port_acl_service(vars->{'port'}, $device, $job->username);

    return Status->done('PortName is able to run');
  }
);

# 注册主阶段工作器
# 执行端口名称设置操作
register_worker(
  {phase => 'main', driver => 'snmp'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $pn, $data) = map { $job->$_ } qw/device port extra/;

    # 直接更新伪设备数据库
    unless ($device->is_pseudo()) {

      # 使用读写社区字符串进行SNMP连接
      my $snmp = App::Netdisco::Transport::SNMP->writer_for($device)
        or return Status->defer("failed to connect to $device to update alias");

      # 获取端口接口ID
      my $iid = get_iid($snmp, vars->{'port'}) or return Status->error("Failed to get port ID for [$pn] from $device");

      # 设置端口别名
      my $rv = $snmp->set_i_alias($data, $iid);

      if (!defined $rv) {
        return Status->error(sprintf 'Failed to set [%s] alias to [%s] on $device: %s', $pn, $data,
          ($snmp->error || ''));
      }

      # 确认设置成功
      $snmp->clear_cache;
      my $state = ($snmp->i_alias($iid) || '');
      if (ref {} ne ref $state or $state->{$iid} ne $data) {
        return Status->error("Verify of [$pn] alias failed on $device");
      }
    }

    # 更新Netdisco数据库
    vars->{'port'}->update({name => $data});

    return Status->done("Updated [$pn] alias on [$device] to [$data]");
  }
);

true;
