package App::Netdisco::Worker::Plugin::Vlan;

# VLAN控制工作器插件
# 提供网络端口VLAN设置功能

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Port ':all';

# 注册检查阶段工作器
# 验证VLAN控制操作的可行性
register_worker(
  {phase => 'check'},
  sub {
    my ($job, $workerconf) = @_;
    my ($device, $port, $data) = map { $job->$_ } qw/device port extra/;

    # 检查设备参数
    return Status->error('Vlan failed: unable to interpret device param') unless defined $device;

    # 检查设备是否已发现
    return Status->error("Vlan skipped: $device not yet discovered") unless $device->in_storage;

    # 检查端口参数
    return Status->error('Missing port (-p).') unless defined $job->port;

    # 获取端口对象
    vars->{'port'} = get_port($device, $port) or return Status->error("Unknown port name [$port] on device $device");

    # 检查VLAN参数
    return Status->error('Missing vlan (-e).') unless defined $job->subaction;

    # 同步端口控制角色并检查VLAN权限
    sync_portctl_roles();
    return Status->error("Permission denied to alter native vlan")
      unless port_acl_pvid(vars->{'port'}, $device, $job->username);

    return Status->done("Vlan is able to run.");
  }
);

true;
