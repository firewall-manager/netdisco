# Netdisco端口电源发现插件
# 此模块提供端口电源发现功能，用于通过SNMP获取网络设备的PoE电源模块和端口电源信息
package App::Netdisco::Worker::Plugin::Discover::PortPower;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

# 注册主阶段工作器 - 发现端口电源信息
register_worker(
  {phase => 'main', driver => 'snmp'},  # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;  # 确保设备已存储
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    # 获取电源模块信息
    my $p_watts  = $snmp->peth_power_watts;   # 电源模块功率
    my $p_status = $snmp->peth_power_status;  # 电源模块状态

    if (!defined $p_watts) {
      return Status->info(sprintf ' [%s] power - 0 power modules', $device->ip);
    }

    # 构建设备电源模块信息，适合DBIC
    my @devicepower;
    foreach my $entry (keys %$p_watts) {
      push @devicepower, {module => $entry, power => $p_watts->{$entry}, status => $p_status->{$entry},};
    }

    # 缓存设备端口以节省数据库查询
    my $device_ports = vars->{'device_ports'} || {map { ($_->port => $_) } $device->ports->all};

    # 获取端口电源相关信息
    my $interfaces = $snmp->interfaces;        # 接口映射
    my $p_ifindex  = $snmp->peth_port_ifindex; # PoE端口接口索引
    my $p_admin    = $snmp->peth_port_admin;   # PoE端口管理状态
    my $p_pstatus  = $snmp->peth_port_status;  # PoE端口状态
    my $p_class    = $snmp->peth_port_class;   # PoE端口类别
    my $p_power    = $snmp->peth_port_power;   # PoE端口功率

    # 构建设备端口电源信息，适合DBIC
    my @portpower;
    foreach my $entry (keys %$p_ifindex) {

      # 获取端口名称
      my $port = $interfaces->{$p_ifindex->{$entry}} or next;

      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] power - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      my ($module) = split m/\./, $entry;  # 提取模块号
      push @portpower, {
        port   => $port,                    # 端口名称
        module => $module,                  # 模块号
        admin  => $p_admin->{$entry},       # 管理状态
        status => $p_pstatus->{$entry},     # 端口状态
        class  => $p_class->{$entry},       # 端口类别
        power  => $p_power->{$entry},       # 端口功率
      };
    }

    # 更新电源模块信息
    schema('netdisco')->txn_do(sub {
      my $gone = $device->power_modules->delete;
      debug sprintf ' [%s] power - removed %d power modules', $device->ip, $gone;
      $device->power_modules->populate(\@devicepower);
      debug sprintf ' [%s] power - added %d new power modules', $device->ip, scalar @devicepower;
    });

    # 更新端口电源信息
    schema('netdisco')->txn_do(sub {
      my $gone = $device->powered_ports->delete;
      debug sprintf ' [%s] power - removed %d PoE capable ports', $device->ip, $gone;
      $device->powered_ports->populate(\@portpower);

      return Status->info(sprintf ' [%s] power - added %d new PoE capable ports', $device->ip, scalar @portpower);
    });
  }
);

true;
