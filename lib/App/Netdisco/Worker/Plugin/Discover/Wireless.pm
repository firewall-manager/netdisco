# Netdisco无线网络发现插件
# 此模块提供无线网络发现功能，用于通过SNMP发现和存储网络设备的无线网络信息（SSID、BSSID、频道、功率）
package App::Netdisco::Worker::Plugin::Discover::Wireless;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use Dancer::Plugin::DBIC 'schema';

# 注册主阶段工作器 - 发现无线网络信息
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    # 获取SSID列表
    my $ssidlist = $snmp->i_ssidlist;
    return unless scalar keys %$ssidlist;    # 如果没有SSID则返回

    # 缓存设备端口以节省数据库查询
    my $device_ports = vars->{'device_ports'} || {map { ($_->port => $_) } $device->ports->all};

    # 获取无线网络相关信息
    my $interfaces = $snmp->interfaces;             # 接口映射
    my $ssidbcast  = $snmp->i_ssidbcast;            # SSID广播状态
    my $ssidmac    = $snmp->i_ssidmac;              # SSID MAC地址
    my $channel    = $snmp->i_80211channel;         # 802.11频道
    my $power      = $snmp->dot11_cur_tx_pwr_mw;    # 当前发射功率（毫瓦）

    # 构建设备SSID列表，适合DBIC
    my (%ssidseen, @ssids);                         # SSID已处理标记和SSID列表
    foreach my $entry (keys %$ssidlist) {
      (my $iid = $entry) =~ s/\.\d+$//;             # 提取接口ID
      my $port = $interfaces->{$iid};

      if (not $port) {
        debug sprintf ' [%s] wireless - ignoring %s (no port mapping)', $device->ip, $iid;
        next;
      }

      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] wireless - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      next unless $ssidmac->{$entry};    # 跳过没有MAC地址的SSID

      # 检查重复的BSSID
      if (exists $ssidseen{$port}{$ssidmac->{$entry}}) {
        debug sprintf ' [%s] wireless - duplicate bssid %s on port %s', $device->ip, $ssidmac->{$entry}, $port;
        next;
      }
      ++$ssidseen{$port}{$ssidmac->{$entry}};    # 标记为已处理

      # 构建SSID记录
      push @ssids,
        {port => $port, ssid => $ssidlist->{$entry}, broadcast => $ssidbcast->{$entry}, bssid => $ssidmac->{$entry},};
    }

    # 存储SSID信息到数据库
    schema('netdisco')->txn_do(sub {
      my $gone = $device->ssids->delete;    # 删除现有SSID
      debug sprintf ' [%s] wireless - removed %d SSIDs', $device->ip, $gone;
      $device->ssids->populate(\@ssids);    # 插入新的SSID
      debug sprintf ' [%s] wireless - added %d new SSIDs', $device->ip, scalar @ssids;
    });

    # 构建设备频道列表，适合DBIC
    my @channels;    # 频道列表
    foreach my $entry (keys %$channel) {
      my $port = $interfaces->{$entry};

      if (not $port) {
        debug sprintf ' [%s] wireless - ignoring %s (no port mapping)', $device->ip, $entry;
        next;
      }

      if (!defined $device_ports->{$port}) {
        debug sprintf ' [%s] wireless - local port %s already skipped, ignoring', $device->ip, $port;
        next;
      }

      # 构建频道记录
      push @channels, {port => $port, channel => $channel->{$entry}, power => $power->{$entry},};
    }

    # 存储无线端口信息到数据库
    schema('netdisco')->txn_do(sub {
      my $gone = $device->wireless_ports->delete;       # 删除现有无线端口
      debug sprintf ' [%s] wireless - removed %d wireless channels', $device->ip, $gone;
      $device->wireless_ports->populate(\@channels);    # 插入新的无线端口

      return Status->info(sprintf ' [%s] wireless - added %d new wireless channels', $device->ip, scalar @channels);
    });
  }
);

true;
