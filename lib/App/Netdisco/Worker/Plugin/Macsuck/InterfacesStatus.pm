# Netdisco接口状态收集插件
# 此模块提供接口状态收集功能，用于通过SNMP获取和更新网络设备接口的UP/DOWN状态
package App::Netdisco::Worker::Plugin::Macsuck::InterfacesStatus;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';
use Dancer::Plugin::DBIC 'schema';

# 注册主阶段工作器 - 从SNMP收集接口状态
register_worker(
  {phase => 'main', driver => 'snmp', title => 'gather interfaces status from snmp'},    # 主阶段，使用SNMP驱动
  sub {

    my ($job, $workerconf) = @_;
    my $device = $job->device;                                                           # 获取设备对象

    # 建立SNMP连接
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->info("skip: could not SNMP connect to $device");

    # 获取接口映射表
    my $interfaces         = $snmp->interfaces || {};                                    # 接口ID到名称的映射
    my $reverse_interfaces = {reverse %{$interfaces}};                                   # 名称到接口ID的反向映射

    # 获取接口状态信息
    my $i_up       = $snmp->i_up;                                                        # 接口运行状态
    my $i_up_admin = $snmp->i_up_admin;                                                  # 接口管理状态

    # 确保端口反映设备报告的最新状态
    foreach my $port (keys %{vars->{'device_ports'}}) {
      my $iid = $reverse_interfaces->{$port} or next;                                    # 获取接口ID

      debug sprintf ' [%s] macsuck - updating port %s status : %s/%s', $device->ip, $port,
        ($i_up_admin->{$iid} || '-'), ($i_up->{$iid} || '-');

      # 更新端口状态
      vars->{'device_ports'}->{$port}->set_column(up       => $i_up->{$iid});            # 设置运行状态
      vars->{'device_ports'}->{$port}->set_column(up_admin => $i_up_admin->{$iid});      # 设置管理状态
    }

    return Status->info('interfaces status from snmp complete');
  }
);

register_worker(
  {phase => 'store', title => 'update interfaces status in database'},
  sub {

    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # make sure ports are UP in netdisco (unless it's a lag master,
    # because we can still see nodes without a functioning aggregate)

    my %port_seen = ();
    foreach my $vlan (reverse sort keys %{vars->{'fwtable'}}) {
      foreach my $port (keys %{vars->{'fwtable'}->{$vlan}}) {
        next if $port_seen{$port};
        ++$port_seen{$port};

        next unless scalar keys %{vars->{'fwtable'}->{$vlan}->{$port}};
        next unless exists vars->{'device_ports'}->{$port};
        next if vars->{'device_ports'}->{$port}->is_master;

        debug sprintf ' [%s] macsuck - updating port %s status up/up due to node presence', $device->ip, $port;

        vars->{'device_ports'}->{$port}->set_column(up       => 'up');
        vars->{'device_ports'}->{$port}->set_column(up_admin => 'up');
      }
    }

    my $updated = 0;
    foreach my $port (values %{vars->{'device_ports'}}) {
      next unless $port->is_changed();
      $port->update();
      ++$updated;
    }

    return Status->info(sprintf '%s interfaces status updated in database', $updated);
  }
);

true;
