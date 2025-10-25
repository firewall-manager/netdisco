# Netdisco VLAN发现插件
# 此模块提供VLAN发现功能，用于通过SNMP发现和存储网络设备的VLAN信息
package App::Netdisco::Worker::Plugin::Discover::VLANs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC 'schema';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP ();

use aliased 'App::Netdisco::Worker::Status';
use List::MoreUtils 'uniq';

# 注册主阶段工作器 - 发现VLAN信息
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    # 获取VLAN名称和索引
    my $v_name  = $snmp->v_name;          # VLAN名称
    my $v_index = $snmp->v_index;         # VLAN索引

    # 缓存设备端口以节省数据库查询
    my $device_ports = vars->{'device_ports'} || {map { ($_->port => $_) } $device->ports->all};

    # 获取VLAN相关信息
    my $i_vlan                     = $snmp->i_vlan;                        # 接口VLAN
    my $i_vlan_type                = $snmp->i_vlan_type;                   # 接口VLAN类型
    my $interfaces                 = $snmp->interfaces;                    # 接口映射
    my $i_vlan_membership          = $snmp->i_vlan_membership;             # VLAN成员关系
    my $i_vlan_membership_untagged = $snmp->i_vlan_membership_untagged;    # 未标记VLAN成员关系

    my %p_seen       = ();                                                                   # 已处理的VLAN
    my @portvlans    = ();                                                                   # 端口VLAN列表
    my @active_ports = uniq(keys %$i_vlan_membership_untagged, keys %$i_vlan_membership);    # 活动端口

    # 构建设备端口VLAN信息，适合DBIC
    foreach my $entry (@active_ports) {
      my $port = $interfaces->{$entry} or next;

      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] vlans - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      my %this_port_vlans = ();                        # 当前端口的VLAN
      my $type            = $i_vlan_type->{$entry};    # VLAN类型

      # 处理未标记VLAN成员关系
      foreach my $vlan (@{$i_vlan_membership_untagged->{$entry} || []}) {
        next unless $vlan;
        next if $this_port_vlans{$vlan};                                                            # 跳过已处理的VLAN
        my $native = ((defined $i_vlan->{$entry}) and ($vlan eq $i_vlan->{$entry})) ? 't' : 'f';    # 是否为原生VLAN

        push @portvlans, {
          port          => $port,                # 端口名称
          vlan          => $vlan,                # VLAN ID
          native        => $native,              # 是否为原生VLAN
          egress_tag    => 'f',                  # 出口标记（未标记）
          vlantype      => $type,                # VLAN类型
          last_discover => \'LOCALTIMESTAMP',    # 最后发现时间
        };

        ++$this_port_vlans{$vlan};
        ++$p_seen{$vlan};
      }

      # 处理标记VLAN成员关系
      foreach my $vlan (@{$i_vlan_membership->{$entry} || []}) {
        next unless $vlan;
        next if $this_port_vlans{$vlan};                                                            # 跳过已处理的VLAN
        my $native = ((defined $i_vlan->{$entry}) and ($vlan eq $i_vlan->{$entry})) ? 't' : 'f';    # 是否为原生VLAN

        push @portvlans, {
          port          => $port,                           # 端口名称
          vlan          => $vlan,                           # VLAN ID
          native        => $native,                         # 是否为原生VLAN
          egress_tag    => ($native eq 't' ? 'f' : 't'),    # 出口标记（原生VLAN不标记，其他标记）
          vlantype      => $type,                           # VLAN类型
          last_discover => \'LOCALTIMESTAMP',               # 最后发现时间
        };

        ++$this_port_vlans{$vlan};
        ++$p_seen{$vlan};
      }
    }

    # 注释：为非原生VLAN的端口设置is_uplink
    # foreach my $pv (@portvlans) {
    #     next unless $pv->{native} and $pv->{native} eq 'f';
    #     $device_ports->{$pv->{port}}->update({is_uplink => \'true'});
    # }

    # 存储端口VLAN信息到数据库
    schema('netdisco')->txn_do(sub {
      my $gone = $device->port_vlans->delete;        # 删除现有端口VLAN
      debug sprintf ' [%s] vlans - removed %d port VLANs', $device->ip, $gone;
      $device->port_vlans->populate(\@portvlans);    # 插入新的端口VLAN

      debug sprintf ' [%s] vlans - added %d new port VLANs', $device->ip, scalar @portvlans;
    });

    my %d_seen      = ();    # 已处理的设备VLAN
    my @devicevlans = ();    # 设备VLAN列表

    # 添加命名VLAN到设备
    foreach my $entry (keys %$v_name) {
      my $vlan = $v_index->{$entry};
      next unless $vlan;
      next unless defined $vlan and $vlan;
      ++$d_seen{$vlan};

      push @devicevlans, {vlan => $vlan, description => $v_name->{$entry}, last_discover => \'LOCALTIMESTAMP',};
    }

    # 同时添加未命名VLAN到设备
    foreach my $vlan (keys %p_seen) {
      next unless $vlan;
      next if $d_seen{$vlan};    # 跳过已处理的VLAN
      push @devicevlans,
        {vlan => $vlan, description => (sprintf "VLAN %d", $vlan), last_discover => \'LOCALTIMESTAMP',};
    }

    # 支持钩子
    vars->{'hook_data'}->{'vlans'} = \@devicevlans;

    # 存储设备VLAN信息到数据库
    schema('netdisco')->txn_do(sub {
      my $gone = $device->vlans->delete;          # 删除现有设备VLAN
      debug sprintf ' [%s] vlans - removed %d device VLANs', $device->ip, $gone;
      $device->vlans->populate(\@devicevlans);    # 插入新的设备VLAN

      debug sprintf ' [%s] vlans - added %d new device VLANs', $device->ip, scalar @devicevlans;
    });

    return Status->info(sprintf ' [%s] vlans - discovered for ports and device', $device->ip);
  }
);

true;
