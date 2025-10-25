# Netdisco设备规范IP地址插件
# 此模块提供设备规范IP地址确定功能，用于通过DNS反向解析或设备身份映射确定设备的规范IP地址
package App::Netdisco::Worker::Plugin::Discover::CanonicalIP;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Transport::SNMP ();
use App::Netdisco::Util::Permission 'acl_matches';
use App::Netdisco::Util::DNS 'ipv4_from_hostname';
use App::Netdisco::Util::Device 'is_discoverable';
use Dancer::Plugin::DBIC 'schema';

# 注册主阶段工作器 - 确定设备规范IP地址
register_worker(
  {phase => 'main', driver => 'snmp'},    # 主阶段，使用SNMP驱动
  sub {
    my ($job, $workerconf) = @_;

    my $device = $job->device;
    return unless $device->in_storage;    # 确保设备已存储
    my $snmp = App::Netdisco::Transport::SNMP->reader_for($device)
      or return Status->defer("discover failed: could not SNMP connect to $device");

    my $old_ip    = $device->ip;                        # 原始IP地址
    my $new_ip    = $old_ip;                            # 新的规范IP地址
    my $revofname = ipv4_from_hostname($snmp->name);    # 从主机名解析IP

    # 如果启用反向系统名解析且解析成功
    if (setting('reverse_sysname') and $revofname) {
      if (App::Netdisco::Transport::SNMP->test_connection($new_ip)) {
        $new_ip = $revofname;    # 使用解析的IP作为规范IP
      }
      else {
        debug sprintf ' [%s] device - cannot renumber to %s - SNMP connect failed', $old_ip, $revofname;
      }
    }

    # 如果配置了设备身份映射
    if (scalar @{setting('device_identity')}) {
      my @idmaps = @{setting('device_identity')};                  # 获取设备身份映射配置
      my @devips = $device->device_ips->order_by('alias')->all;    # 获取设备IP别名

      # 使用ALIASMAP中断，确保在第一次成功重编号后停止

    ALIASMAP: foreach my $map (@idmaps) {
        next unless ref {} eq ref $map;                            # 跳过非哈希引用

        foreach my $key (sort keys %$map) {

          # 左侧匹配设备，右侧匹配设备IP
          next unless $key and $map->{$key};
          next unless acl_matches($device, $key);                  # 检查设备是否匹配

          foreach my $alias (@devips) {
            next if $alias->alias eq $old_ip;                      # 跳过原始IP
            next unless acl_matches($alias, $map->{$key});         # 检查别名是否匹配

            # 检查别名是否可发现
            if (not is_discoverable($alias->alias)) {
              debug sprintf ' [%s] device - cannot renumber to %s - not discoverable', $old_ip, $alias->alias;
              next;
            }

            # 测试SNMP连接到别名IP
            if (App::Netdisco::Transport::SNMP->test_connection($alias->alias)) {
              $new_ip = $alias->alias;    # 使用别名作为规范IP
              last ALIASMAP;              # 找到后退出
            }
            else {
              debug sprintf ' [%s] device - cannot renumber to %s - SNMP connect failed', $old_ip, $alias->alias;
            }
          }
        }
      }
    }

    return if $new_ip eq $old_ip;    # 如果IP没有变化则返回

    # 执行设备重编号
    schema('netdisco')->txn_do(sub {

      # 查找具有相同厂商和序列号的现有设备
      my $existing
        = schema('netdisco')
        ->resultset('Device')
        ->search({ip => $new_ip, vendor => $device->vendor, serial => $device->serial,});

      # 如果是新设备且已存在相同设备，删除当前设备
      if (vars->{'new_device'} and $existing->count) {
        $device->delete;
        return $job->cancel(" [$old_ip] device - cancelling fresh discover: already known as $new_ip");
      }

      # 发现现有设备但更改IP，需要删除现有设备
      $existing->delete;

      # 如果目标设备存在则此操作会失败
      $device->renumber($new_ip) or die "cannot renumber to: $new_ip";    # 回滚

      # 重编号操作中未完成，但需要更新作业记录
      schema('netdisco')->resultset('Admin')->find({job => $job->id})->update({device => $new_ip}) if $job->id;

      return Status->info(sprintf ' [%s] device - changed IP to %s (%s)', $old_ip, $device->ip, ($device->dns || ''));
    });
  }
);

true;
