# Netdisco NetBIOS状态核心工作插件
# 此模块提供NetBIOS状态查询的核心功能，用于通过nbtstat命令获取网络中节点的NetBIOS信息
package App::Netdisco::Worker::Plugin::Nbtstat::Core;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use App::Netdisco::Util::Nbtstat qw/nbtstat_resolve_async store_nbt/;
use App::Netdisco::Util::Node 'is_nbtstatable';
use Dancer::Plugin::DBIC 'schema';
use Time::HiRes 'gettimeofday';

# 注册主阶段工作器 - 执行NetBIOS状态查询
register_worker(
  {phase => 'main'},  # 主阶段工作器
  sub {
    my ($job, $workerconf) = @_;
    my $host = $job->device->ip;  # 获取设备IP地址

    # 获取设备上的节点列表
    my $interval = (setting('nbtstat_max_age') || 7) . ' day';  # 获取nbtstat最大年龄设置，默认7天
    my $rs       = schema('netdisco')->resultset('NodeIp')->search(
      {
        -bool          => 'me.active',           # 节点IP活跃
        -bool          => 'nodes.active',        # 节点活跃
        'nodes.switch' => $host,                  # 节点连接的交换机
        'me.time_last' => \['>= LOCALTIMESTAMP - ?::interval', $interval],  # 时间在指定间隔内
      },
      {join => 'nodes', columns => 'ip', distinct => 1,}  # 连接节点表，选择IP列，去重
    )->ip_version(4);  # 只查询IPv4地址

    # 过滤可进行nbtstat查询的IP地址
    my @ips = map { +{'ip' => $_} } grep { is_nbtstatable($_) } $rs->get_column('ip')->all;

    # 如果有IP地址，执行nbtstat查询
    if (scalar @ips) {
      my $now            = 'to_timestamp(' . (join '.', gettimeofday) . ')::timestamp';  # 当前时间戳
      my $resolved_nodes = nbtstat_resolve_async(\@ips);  # 异步解析NetBIOS名称

      # 更新node_nbt表的状态条目
      foreach my $result (@$resolved_nodes) {
        if (defined $result->{'nbname'}) {  # 如果解析到NetBIOS名称
          store_nbt($result, $now);  # 存储NetBIOS信息
        }
      }
    }

    return Status->done("Ended nbtstat for $host");  # 返回完成状态
  }
);

true;
