# Netdisco路由邻居发现插件
# 此模块提供路由邻居发现功能，用于通过SNMP发现和存储网络设备的路由邻居信息（OSPF、BGP、IS-IS、EIGRP对等体）
package App::Netdisco::Worker::Plugin::Discover::NextHopNeighbors;
use Dancer ':syntax';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::JobQueue 'jq_insert';
use NetAddr::IP;

# 注册主阶段工作器 - 发现路由邻居
register_worker(
  {phase => 'main', driver => 'snmp'},  # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;

    # 检查设备是否已存储且具有第3层功能或强制arpnip或忽略层
    return
      unless $device->in_storage
      and ($device->has_layer(3) or acl_matches($device, 'force_arpnip') or acl_matches($device, 'ignore_layers'));

    # 检查路由邻居发现是否被禁用
    if ( acl_matches($device, 'skip_neighbors')
      or not setting('discover_neighbors')
      or not setting('discover_routed_neighbors')) {

      return Status->info(sprintf ' [%s] neigh - routed neighbor discovery is disabled on this device', $device->ip);
    }

    # 建立SNMP连接
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    # 获取各种路由协议的对等体信息
    my $ospf_peers   = $snmp->ospf_peers    || {};  # OSPF对等体
    my $ospf_routers = $snmp->ospf_peer_id  || {};  # OSPF路由器ID
    my $isis_peers   = $snmp->isis_peers    || {};  # IS-IS对等体
    my $bgp_peers    = $snmp->bgp_peer_addr || {};  # BGP对等体地址
    my $eigrp_peers  = $snmp->eigrp_peers   || {};  # EIGRP对等体

    # 检查是否有任何路由协议对等体
    return Status->info(" [$device] neigh - no BGP, OSPF, IS-IS, or EIGRP peers")
      unless ((scalar values %$ospf_peers)
      or (scalar values %$ospf_routers)
      or (scalar values %$bgp_peers)
      or (scalar values %$eigrp_peers)
      or (scalar values %$isis_peers));

    # 收集所有路由对等体IP地址
    foreach my $ip (
      (values %$ospf_peers),    # OSPF对等体IP
      (values %$ospf_routers),  # OSPF路由器ID
      (values %$bgp_peers),     # BGP对等体IP
      (values %$eigrp_peers),   # EIGRP对等体IP
      (values %$isis_peers)     # IS-IS对等体IP
    ) {

      push @{vars->{'next_hops'}}, $ip;  # 添加到下一跳列表
    }

    return Status->info(sprintf " [%s] neigh - found %s routed peers.", $device, scalar @{vars->{'next_hops'}});
  }
);

# 注册存储阶段工作器 - 存储路由邻居
register_worker(
  {phase => 'store'},  # 存储阶段
  sub {
    my ($job, $workerconf) = @_;
    my $device = $job->device;

    my $nh = vars->{'next_hops'};  # 获取下一跳列表
    return unless ref [] eq ref $nh and scalar @$nh;  # 检查是否为数组且非空

    my $count = 0;  # 排队计数器
    foreach my $host (@$nh) {
      my $ip = NetAddr::IP->new($host);  # 创建IP地址对象
      
      # 跳过无效IP地址
      if (not $ip or $ip->addr eq '0.0.0.0' or acl_matches($ip->addr, 'group:__LOOPBACK_ADDRESSES__')) {
        debug sprintf ' [%s] neigh - skipping routed peer %s is not valid', $device, $host;
        next;
      }

      my $peer = get_device($ip);  # 获取对等设备
      next if $peer->in_storage or not is_discoverable($peer);  # 跳过已存储或不可发现的设备
      next if vars->{'queued'}->{$peer->ip};  # 跳过已排队的设备

      # 将设备加入发现队列
      jq_insert({device => $peer->ip, action => 'discover',});

      $count++;
      vars->{'queued'}->{$peer->ip} += 1;  # 标记为已排队
      debug sprintf ' [%s] neigh - queued %s for discovery (peer)', $device, $peer->ip;
    }

    return Status->info(" [$device] neigh - $count peers added to queue.");
  }
);

true;
