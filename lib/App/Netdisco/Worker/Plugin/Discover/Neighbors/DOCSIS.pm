# Netdisco DOCSIS邻居发现插件
# 此模块提供DOCSIS邻居发现功能，用于发现和发现通过DOCSIS协议连接的调制解调器设备
package App::Netdisco::Worker::Plugin::Discover::Neighbors::DOCSIS;
use Dancer ':syntax';

use App::Netdisco::Worker::Plugin;
use App::Netdisco::Transport::SNMP;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Device qw/get_device is_discoverable/;
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::JobQueue 'jq_insert';

# 注册主阶段工作器 - 发现DOCSIS邻居
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储

    # 检查邻居发现是否被禁用
    if (acl_matches($device, 'skip_neighbors') or not setting('discover_neighbors')) {
      return Status->info(sprintf ' [%s] neigh - DOCSIS modems discovery is disabled on this device', $device->ip);
    }

    # 建立SNMP连接
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    # 获取DOCSIS调制解调器信息
    my $modems = $snmp->docs_if_cmts_cm_status_inet_address() || {};

    # 如果没有调制解调器，可能不是DOCSIS设备
    return Status->info(" [$device] neigh - no modems (probably not a DOCSIS device)") unless (scalar values %$modems);

    my $count = 0;
    foreach my $ip (values %$modems) {

      # 某些调制解调器可能已注册，但没有分配IP地址（可能离线、禁用等）
      next if $ip eq '';

      my $peer = get_device($ip);                                 # 获取对等设备
      next if $peer->in_storage or not is_discoverable($peer);    # 跳过已存储或不可发现的设备
      next if vars->{'queued'}->{$ip};                            # 跳过已排队的设备

      # 将设备加入发现队列
      jq_insert({device => $ip, action => 'discover',});

      $count++;
      vars->{'queued'}->{$ip} += 1;                               # 标记为已排队
      debug sprintf ' [%s] queue - queued %s for discovery (DOCSIS peer)', $device, $ip;
    }

    return Status->info(" [$device] neigh - $count DOCSIS peers (modems) added to queue.");
  }
);

true;
