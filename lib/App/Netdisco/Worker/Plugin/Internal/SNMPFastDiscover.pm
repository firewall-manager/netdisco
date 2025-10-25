# Netdisco SNMP快速发现内部插件
# 此模块提供SNMP快速发现功能，用于在初始发现阶段使用更快的SNMP超时设置
package App::Netdisco::Worker::Plugin::Internal::SNMPFastDiscover;

use Dancer ':syntax';
use App::Netdisco::Worker::Plugin;
use aliased 'App::Netdisco::Worker::Status';

use Scalar::Util 'blessed';

# 注册检查阶段工作器 - 设置SNMP快速发现超时
register_worker(
  {phase => 'check', driver => 'direct'},    # 检查阶段，直接驱动
  sub {
    my ($job, $workerconf) = @_;

    # 如果作业是排队的作业，且是发现动作，且是第一个...
    if (
      $job->job and $job->action eq 'discover'    # 发现动作
      and not $job->log                           # 没有日志
      and (not blessed $job->device or not $job->device->in_storage)
    ) {                                           # 设备不在存储中

      config->{'snmp_try_slow_connect'} = false;                       # 禁用慢速连接尝试
      debug "running with fast SNMP timeouts for initial discover";    # 使用快速SNMP超时进行初始发现
    }
    else {
      debug "running with configured SNMP timeouts";                   # 使用配置的SNMP超时
    }
  }
);

true;
