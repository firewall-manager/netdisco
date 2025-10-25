# Netdisco ARP/IP子网收集插件
# 此模块提供ARP/IP子网收集功能，用于通过SNMP或CLI收集网络设备的直连子网信息
package App::Netdisco::Worker::Plugin::Arpnip::Subnets;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use Dancer::Plugin::DBIC 'schema';
use NetAddr::IP::Lite ':lower';
use Time::HiRes 'gettimeofday';

# 注册主阶段工作器 - 通过SNMP收集子网信息
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    my $snmp   = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("arpnip failed: could not SNMP connect to $device");

    # 获取直连网络
    my @subnets = gather_subnets($device);

    # TODO: IPv6子网支持

    # 存储子网信息到数据库
    my $now = 'to_timestamp(' . (join '.', gettimeofday) . ')::timestamp';
    store_subnet($_, $now) for @subnets;

    return Status->info(sprintf ' [%s] arpnip - processed %s Subnet entries', $device->ip, scalar @subnets);
  }
);

# 注册主阶段工作器 - 通过CLI收集子网信息
register_worker(
  {phase => 'main', driver => 'cli'},    # 主阶段，使用CLI驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    my $cli    = App::Netdisco::Transport::SSH->session_for($device)
      or return Status->defer("arpnip (cli) failed: could not SSH connect to $device");

    # 通过CLI获取子网信息
    my @subnets = grep { defined and length } $cli->subnets;

    # 存储子网信息到数据库
    my $now = 'to_timestamp(' . (join '.', gettimeofday) . ')::timestamp';
    debug sprintf ' [%s] arpnip (cli) - found subnet %s', $device->ip, $_ for @subnets;
    store_subnet($_, $now) for @subnets;

    return Status->info(sprintf ' [%s] arpnip (cli) - processed %s Subnet entries', $device->ip, scalar @subnets);
  }
);

# 收集设备子网信息
sub gather_subnets {
  my $device  = shift;
  my @subnets = ();

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device) or return ();    # 已经检查过！

  # 获取IP网络掩码信息
  my $ip_netmask = $snmp->ip_netmask;
  foreach my $entry (keys %$ip_netmask) {
    my $ip   = NetAddr::IP::Lite->new($entry) or next;
    my $addr = $ip->addr;

    # 跳过无效地址
    next if $addr eq '0.0.0.0';
    next if acl_matches($ip, 'group:__LOOPBACK_ADDRESSES__');      # 跳过回环地址
    next if setting('ignore_private_nets') and $ip->is_rfc1918;    # 跳过私有网络

    # 获取网络掩码
    my $netmask = $ip_netmask->{$addr} || $ip->bits();
    next if $netmask eq '255.255.255.255' or $netmask eq '0.0.0.0';    # 跳过主机地址和默认路由

    # 构建CIDR格式的子网
    my $cidr = NetAddr::IP::Lite->new($addr, $netmask)->network->cidr;

    debug sprintf ' [%s] arpnip - found subnet %s', $device->ip, $cidr;
    push @subnets, $cidr;
  }

  return @subnets;
}

# 更新子网信息到数据库
sub store_subnet {
  my ($subnet, $now) = @_;
  return unless $subnet;

  # 使用事务更新或创建子网记录
  schema('netdisco')->txn_do(sub {
    schema('netdisco')
      ->resultset('Subnet')
      ->update_or_create({net => $subnet, last_discover => \$now,}, {for => 'update'});
  });
}

true;
