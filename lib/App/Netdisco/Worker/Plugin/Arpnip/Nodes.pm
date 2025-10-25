# Netdisco ARP/IP节点收集插件
# 此模块提供ARP/IP节点收集功能，用于通过SNMP、CLI或直接数据源收集网络设备的ARP表和IPv6邻居缓存
package App::Netdisco::Worker::Plugin::Arpnip::Nodes;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SSH  ();
use App::Netdisco::Transport::SNMP ();

use App::Netdisco::Util::Node qw/check_mac store_arp/;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';

use NetAddr::IP::Lite ':lower';
use Regexp::Common 'net';
use NetAddr::MAC ();
use Time::HiRes 'gettimeofday';

# 注册早期阶段工作器 - 准备通用数据
register_worker(
  {phase => 'early', title => 'prepare common data'},    # 早期阶段，准备通用数据
  sub {

    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # 设置时间戳，使用相同值便于后续处理
    vars->{'timestamp'} = ($job->is_offline and $job->entered)    # 离线作业使用进入时间
      ? (schema('netdisco')->storage->dbh->quote($job->entered) . '::timestamp')
      : 'to_timestamp(' . (join '.', gettimeofday) . ')::timestamp';    # 在线作业使用当前时间

    # 初始化缓存
    vars->{'arps'} = [];
  }
);

# 注册存储阶段工作器 - 存储ARP/IP节点数据
register_worker(
  {phase => 'store'},    # 存储阶段
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # 过滤有效的MAC地址
    vars->{'arps'} = [grep { check_mac(($_->{mac} || $_->{node}), $device) } @{vars->{'arps'}}];

    # 异步解析主机名
    debug sprintf ' resolving %d ARP entries with max %d outstanding requests', scalar @{vars->{'arps'}},
      $ENV{'PERL_ANYEVENT_MAX_OUTSTANDING_DNS'};
    vars->{'arps'} = hostnames_resolve_async(vars->{'arps'});

    # 统计IPv4和IPv6条目数量
    my ($v4, $v6) = (0, 0);
    foreach my $a_entry (@{vars->{'arps'}}) {
      my $a_ip = NetAddr::IP::Lite->new($a_entry->{ip});

      if ($a_ip) {
        ++$v4 if $a_ip->bits == 32;     # IPv4地址
        ++$v6 if $a_ip->bits == 128;    # IPv6地址
      }
    }

    # 存储ARP条目到数据库
    my $now = vars->{'timestamp'};
    store_arp(\%$_, $now, $device->ip) for @{vars->{'arps'}};

    debug sprintf ' [%s] arpnip - processed %s ARP Cache entries',           $device->ip, $v4;
    debug sprintf ' [%s] arpnip - processed %s IPv6 Neighbor Cache entries', $device->ip, $v6;

    # 更新设备最后arpnip时间
    my $status = $job->best_status;
    if (Status->$status->level == Status->done->level) {
      $device->update({last_arpnip => \$now});
    }

    return Status->$status("Ended arpnip for $device");
  }
);

# 注册主阶段工作器 - 通过SNMP收集ARP表
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    my $snmp   = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("arpnip failed: could not SNMP connect to $device");

    # 缓存IPv4 ARP表
    push @{vars->{'arps'}}, get_arps_snmp($device, $snmp->at_paddr, $snmp->at_netaddr);

    # 缓存IPv6邻居缓存
    push @{vars->{'arps'}}, get_arps_snmp($device, $snmp->ipv6_n2p_mac, $snmp->ipv6_n2p_addr);

    return Status->done("Gathered arp caches from $device");
  }
);

# 获取ARP表（IPv4或IPv6）
sub get_arps_snmp {
  my ($device, $paddr, $netaddr) = @_;
  my @arps = ();

  # 遍历物理地址和网络地址映射
  while (my ($arp, $node) = each %$paddr) {
    my $ip = $netaddr->{$arp} or next;                       # 获取对应的IP地址
    push @arps, {mac => $node, ip => $ip, dns => undef,};    # 构建ARP条目
  }

  return @arps;
}

# 注册主阶段工作器 - 通过CLI收集ARP表
register_worker(
  {phase => 'main', driver => 'cli'},    # 主阶段，使用CLI驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    my $cli    = App::Netdisco::Transport::SSH->session_for($device)
      or return Status->defer("arpnip failed: could not SSH connect to $device");

    # 应该包含IPv4和IPv6
    vars->{'arps'} = [$cli->arpnip];    # 通过CLI获取ARP表

    return Status->done("Gathered arp caches from $device");
  }
);

# 注册主阶段工作器 - 通过直接数据源收集ARP表
register_worker(
  {phase => 'main', driver => 'direct'},    # 主阶段，使用直接驱动
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # 只有离线作业才处理直接数据
    return Status->info('skip: arp table data supplied by other source') unless $job->is_offline;

    # 从文件加载缓存或从作业参数复制
    my $data = $job->extra;
    my @arps = (length $data ? @{from_json($data)} : ());

    return $job->cancel('data provided but 0 arp entries found') unless scalar @arps;

    debug sprintf ' [%s] arpnip - %s arp table entries provided', $device->ip, scalar @arps;

    # 数据完整性检查
    foreach my $a_entry (@arps) {
      my $ip  = NetAddr::IP::Lite->new($a_entry->{'ip'} || '');
      my $mac = NetAddr::MAC->new(mac => ($a_entry->{'mac'} || ''));

      next unless $ip and $mac;                                                                           # 跳过无效的IP或MAC
      next if (($ip->addr eq '0.0.0.0') or ($ip !~ m{^(?:$RE{net}{IPv4}|$RE{net}{IPv6})(?:/\d+)?$}i));    # 跳过无效IP
      next if (($mac->as_ieee eq '00:00:00:00:00:00') or ($mac->as_ieee !~ m{^$RE{net}{MAC}$}i));         # 跳过无效MAC

      push @{vars->{'arps'}}, $a_entry;                                                                   # 添加有效的ARP条目
    }

    return Status->done("Received arp cache for $device");
  }
);

true;
