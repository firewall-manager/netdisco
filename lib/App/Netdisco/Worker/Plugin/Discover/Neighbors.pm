# Netdisco设备邻居发现插件
# 此模块提供设备邻居发现功能，用于通过SNMP发现和存储网络设备的端口邻居信息
package App::Netdisco::Worker::Plugin::Discover::Neighbors;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Device    qw/get_device is_discoverable match_to_setting/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::JobQueue 'jq_insert';
use Dancer::Plugin::DBIC 'schema';
use List::Util 'pairs';
use NetAddr::IP::Lite ();
use NetAddr::MAC;
use Encode;
use Try::Tiny;

=head2 discover_new_neighbors( )

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

Any discovered neighbor unknown to Netdisco will have a C<discover> job
immediately queued (subject to the filtering by the C<discover_*> settings).

=cut

# 注册主阶段工作器 - 发现设备邻居
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储

    # 检查邻居发现是否被禁用
    if (acl_matches($device, 'skip_neighbors') or not setting('discover_neighbors')) {
      return Status->info(sprintf ' [%s] neigh - neighbor discovery is disabled on this device', $device->ip);
    }

    # 建立SNMP连接
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    # 存储邻居信息并获取要发现的设备列表
    my @to_discover = store_neighbors($device);
    my (%seen_id, %seen_ip) = ((), ());    # 跟踪已处理的ID和IP

    # 只对尚未发现的设备排队，且discover_*配置允许发现
    foreach my $neighbor (@to_discover) {
      my ($ip, $remote_id) = @$neighbor;

      # 跳过已排队的IP
      if ($seen_ip{$ip}++) {
        debug sprintf ' queue - skip: IP %s is already queued from %s', $ip, $device->ip;
        next;
      }

      # 跳过已排队的远程ID
      if ($remote_id and $seen_id{$remote_id}++) {
        debug sprintf ' queue - skip: %s with ID [%s] already queued from %s', $ip, $remote_id, $device->ip;
        next;
      }

      my $newdev = get_device($ip);
      next if $newdev->in_storage;    # 跳过已存储的设备

      # 风险：可能出现问题...?
      # https://quickview.cloudapps.cisco.com/quickview/bug/CSCur12254

      # 将设备加入发现队列
      jq_insert({device => $ip, action => 'discover', ($remote_id ? (device_key => $remote_id) : ()),});

      vars->{'queued'}->{$ip} = true;    # 标记为已排队
      debug sprintf ' [%s] queue - queued %s for discovery (ID: [%s])', $device, $ip, ($remote_id || '');
    }

    return Status->info(sprintf ' [%s] neigh - processed %s neighbors', $device->ip, scalar @to_discover);
  }
);

=head2 store_neighbors( $device )

returns: C<@to_discover>

Given a Device database object, and a working SNMP connection, discover and
store the device's port neighbors information.

Entries in the Topology database table will override any discovered device
port relationships.

The Device database object can be a fresh L<DBIx::Class::Row> object which is
not yet stored to the database.

A list of discovered neighbors will be returned as [C<$ip>, C<$type>] tuples.

=cut

# 存储邻居信息并返回要发现的设备列表
sub store_neighbors {
  my $device      = shift;
  my @to_discover = ();

  my $snmp = App::Netdisco::Transport::SNMP->reader_for($device) or return ();    # 已经检查过！

  # 首先允许设置任何手动配置的拓扑
  # 在缓存vars->{'device_ports'}中的行之前执行此操作
  set_manual_topology($device);

  # 检查邻居协议是否启用
  if (!defined $snmp->has_topo) {
    debug sprintf ' [%s] neigh - neighbor protocols are not enabled', $device->ip;
    return @to_discover;
  }

  # 获取SNMP接口和邻居信息
  my $interfaces = $snmp->interfaces;    # 接口映射
  my $c_if       = $snmp->c_if;          # CDP接口
  my $c_port     = $snmp->c_port;        # CDP端口
  my $c_id       = $snmp->c_id;          # CDP ID
  my $c_platform = $snmp->c_platform;    # CDP平台
  my $c_cap      = $snmp->c_cap;         # CDP能力

  # 缓存设备端口以节省数据库查询
  vars->{'device_ports'} = {map { ($_->port => $_) } $device->ports->reset->all};
  my $device_ports = vars->{'device_ports'};

  # IPv4和IPv6邻居表
  my $c_ip   = ($snmp->c_ip || {});                                                              # CDP IP地址
  my %c_ipv6 = %{($snmp->can('hasLLDP') and $snmp->hasLLDP) ? ($snmp->lldp_ipv6 || {}) : {}};    # LLDP IPv6地址

  # 删除未定义值的键，与c_ip保持一致
  delete @c_ipv6{grep { not defined $c_ipv6{$_} } keys %c_ipv6};

  # 允许从IPv6回退到IPv4
  my %success_with_index = ();

NEIGHBOR:
  foreach my $pair ((sort { $a->key cmp $b->key } pairs %c_ipv6), (sort { $a->key cmp $b->key } pairs %$c_ip)) {

    my ($entry, $c_ip_entry) = (@$pair);
    next unless defined $entry and defined $c_ip_entry;

    if (!defined $c_if->{$entry} or !defined $interfaces->{$c_if->{$entry}}) {
      debug sprintf ' [%s] neigh - port for IID:%s not resolved, skipping', $device->ip, $entry;
      next NEIGHBOR;
    }

    # WRT #475 this is SAFE because we check against known ports below
    my $port    = $interfaces->{$c_if->{$entry}} or next NEIGHBOR;
    my $portrow = $device_ports->{$port};

    if (!defined $portrow) {
      debug sprintf ' [%s] neigh - local port %s already skipped, ignoring', $device->ip, $port;
      next NEIGHBOR;
    }

    if (ref $c_ip_entry) {
      debug sprintf ' [%s] neigh - port %s has multiple neighbors - skipping', $device->ip, $port;
      next NEIGHBOR;
    }

    if ($portrow->manual_topo) {
      debug sprintf ' [%s] neigh - %s has manually defined topology', $device->ip, $port;
      next NEIGHBOR;
    }

    my $remote_ip   = $c_ip_entry;
    my $remote_port = undef;
    my $remote_type = Encode::decode('UTF-8', $c_platform->{$entry} || '');
    my $remote_id   = Encode::decode('UTF-8', $c_id->{$entry});
    my $remote_cap  = $c_cap->{$entry} || [];

    next NEIGHBOR unless $remote_ip;
    my $r_netaddr = NetAddr::IP::Lite->new($remote_ip);

    if ($r_netaddr and ($r_netaddr->addr ne $remote_ip)) {
      debug sprintf ' [%s] neigh - IP on %s: using %s as canonical form of %s', $device->ip, $port, $r_netaddr->addr,
        $remote_ip;
      $remote_ip = $r_netaddr->addr;
    }

    if ($remote_ip and acl_matches($remote_ip, 'group:__LOCAL_ADDRESSES__')) {
      debug sprintf ' [%s] neigh - %s is a non-unique local address - skipping', $device->ip, $remote_ip;
      next NEIGHBOR;
    }

    if ($remote_type and match_to_setting($remote_type, 'neighbor_no_type')) {
      debug sprintf ' [%s] neigh - %s has type %s matching neighbor_no_type - skipping', $device->ip, $remote_ip,
        $remote_type;
      next NEIGHBOR;
    }

    # a bunch of heuristics to search known devices if we do not have a
    # useable remote IP...

    if ((!$r_netaddr) or ($remote_ip eq '0.0.0.0') or acl_matches($remote_ip, 'group:__LOOPBACK_ADDRESSES__')) {

      if ($remote_id) {
        my $devices = schema('netdisco')->resultset('Device');

        debug sprintf ' [%s] neigh - bad address %s on port %s, searching for %s instead', $device->ip, $remote_ip,
          $port, $remote_id;
        my $neigh_rs = $devices->search_rs({name => $remote_id});
        my $neigh    = ($neigh_rs->count == 1 ? $neigh_rs->first : undef);

        if (!defined $neigh and $neigh_rs->count) {
          debug sprintf ' [%s] neigh - multiple devices claim to be %s (port %s) - skipping', $device->ip, $remote_id,
            $port;
          next NEIGHBOR;
        }

        if (!defined $neigh) {
          my $mac = NetAddr::MAC->new(mac => ($remote_id || ''));
          if ($mac and not $mac->errstr) {
            $neigh = $devices->single({mac => $mac->as_ieee});
          }
        }

        # some HP switches send 127.0.0.1 as remote_ip if no ip address
        # on default vlan for HP switches remote_ip looks like
        # "myswitchname(012345-012345)"
        if (!defined $neigh) {
          (my $tmpid = $remote_id) =~ s/.*\(([0-9a-f]{6})-([0-9a-f]{6})\).*/$1$2/;
          my $mac = NetAddr::MAC->new(mac => ($tmpid || ''));
          if ($mac and not $mac->errstr) {
            debug sprintf ' [%s] neigh - trying to find neighbor %s by MAC %s', $device->ip, $remote_id, $mac->as_ieee;
            $neigh = $devices->single({mac => $mac->as_ieee});
          }
        }

        if (!defined $neigh) {
          (my $shortid = $remote_id) =~ s/\..*//;
          $neigh = $devices->single({name => {-ilike => "${shortid}%"}});
        }

        if ($neigh) {
          $remote_ip = $neigh->ip;
          debug sprintf ' [%s] neigh - found %s with IP %s', $device->ip, $remote_id, $remote_ip;
        }
        else {
          debug sprintf ' [%s] neigh - could not find %s, skipping', $device->ip, $remote_id;
          next NEIGHBOR;
        }
      }
      else {
        debug sprintf ' [%s] neigh - skipping unuseable address %s on port %s', $device->ip, $remote_ip, $port;
        next NEIGHBOR;
      }
    }

    if (++$success_with_index{$entry} > 1) {
      debug sprintf ' [%s] neigh - port for IID:%s already got a neighbor, skipping', $device->ip, $entry;
      next NEIGHBOR;
    }

    # what we came here to do.... discover the neighbor
    debug sprintf ' [%s] neigh - %s with ID [%s] on %s', $device->ip, $remote_ip, ($remote_id || ''), $port;

    if (is_discoverable($remote_ip, $remote_type, $remote_cap)) {
      push @to_discover, [$remote_ip, $remote_id];
    }
    else {
      debug sprintf ' [%s] neigh - skip: %s of type [%s] excluded by discover_* config', $device->ip, $remote_ip,
        ($remote_type || '');
    }

    $remote_port = $c_port->{$entry};
    if (defined $remote_port) {

      # clean weird characters
      $remote_port =~ s/[^\d\s\/\.,"()\w:-]+//gi;
    }
    else {
      debug sprintf ' [%s] neigh - no remote port found for port %s at %s', $device->ip, $port, $remote_ip;
    }

    $portrow = $portrow->update({
      remote_ip   => $remote_ip,
      remote_port => $remote_port,
      remote_type => $remote_type,
      remote_id   => $remote_id,
      is_uplink   => \"true",
      manual_topo => \"false",
    })->discard_changes();

    # update master of our aggregate to be a neighbor of
    # the master on our peer device (a lot of iffs to get there...).
    # & cannot use ->neighbor prefetch because this is the port insert!
    if (defined $portrow->slave_of) {

      my $peer_device = get_device($remote_ip);
      my $master = schema('netdisco')->resultset('DevicePort')->single({ip => $device->ip, port => $portrow->slave_of});

      if (  $peer_device
        and $peer_device->in_storage
        and $master
        and not($portrow->is_master or defined $master->slave_of)) {

        my $peer_port
          = schema('netdisco')
          ->resultset('DevicePort')
          ->single({ip => $peer_device->ip, port => $portrow->remote_port,});

        $master->update({
          remote_ip   => ($peer_device->ip || $remote_ip),
          remote_port => ($peer_port ? $peer_port->slave_of : undef),
          is_uplink   => \"true",
          is_master   => \"true",
          manual_topo => \"false",
        });
      }
    }
  }

  return @to_discover;
}

# take data from the topology table and update remote_ip and remote_port
# in the devices table. only use root_ips and skip any bad topo entries.
sub set_manual_topology {
  my $device = shift;
  my $snmp   = App::Netdisco::Transport::SNMP->reader_for($device) or return;

  schema('netdisco')->txn_do(sub {

    # clear manual topology flags
    schema('netdisco')->resultset('DevicePort')->search({ip => $device->ip})->update({manual_topo => \'false'});

    # clear outdated manual topology links
    my $old_links = schema('netdisco')->resultset('Topology')->search({
      -or => [
        {dev1 => $device->ip, port1 => {'-not_in' => $device->ports->get_column('port')->as_query}},
        {dev2 => $device->ip, port2 => {'-not_in' => $device->ports->get_column('port')->as_query}},
      ],
    })->delete;
    debug sprintf ' [%s] neigh - removed %d outdated manual topology links', $device->ip, $old_links;

    my $topo_links
      = schema('netdisco')->resultset('Topology')->search({-or => [dev1 => $device->ip, dev2 => $device->ip]});
    debug sprintf ' [%s] neigh - setting manual topology links', $device->ip;

    while (my $link = $topo_links->next) {

      # could fail for broken topo, but we ignore to try the rest
      try {
        schema('netdisco')->txn_do(sub {

          # only work on root_ips
          my $left  = get_device($link->dev1);
          my $right = get_device($link->dev2);

          # skip bad entries
          return unless ($left->in_storage and $right->in_storage);

          $left->ports->single({port => $link->port1})->update({
            remote_ip   => $right->ip,
            remote_port => $link->port2,
            remote_type => undef,
            remote_id   => undef,
            is_uplink   => \"true",
            manual_topo => \"true",
          });

          $right->ports->single({port => $link->port2})->update({
            remote_ip   => $left->ip,
            remote_port => $link->port1,
            remote_type => undef,
            remote_id   => undef,
            is_uplink   => \"true",
            manual_topo => \"true",
          });
        });
      };
    }
  });
}

true;
