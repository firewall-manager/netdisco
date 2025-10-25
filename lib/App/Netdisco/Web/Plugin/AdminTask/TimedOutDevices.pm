# Netdisco 超时设备管理插件
# 此模块提供SNMP连接失败设备的管理功能，用于处理轮询超时的设备
package App::Netdisco::Web::Plugin::AdminTask::TimedOutDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::FastResolver 'hostnames_resolve_async';
use App::Netdisco::DB::ExplicitLocking ':modes';

# 注册管理任务 - SNMP连接失败设备管理
register_admin_task({tag => 'timedoutdevices', label => 'SNMP Connect Failures',});

# 删除超时设备路由 - 重置设备的延迟计数
ajax '/ajax/control/admin/timedoutdevices/del' => require_role admin => sub {
  send_error('Missing backend', 400) unless param('backend');    # 验证后端参数
  send_error('Missing device',  400) unless param('device');     # 验证设备参数

  # 使用排他锁在事务中重置设备延迟计数
  schema(vars->{'tenant'})->resultset('DeviceSkip')->txn_do_locked(
    EXCLUSIVE,
    sub {
      # 查找或创建设备跳过记录，并将延迟计数重置为0
      schema(vars->{'tenant'})->resultset('DeviceSkip')->find_or_create(
        {
          backend => param('backend'),    # 后端标识
          device  => param('device'),     # 设备IP
        },
        {key => 'device_skip_pkey'}
      )->update({deferrals => 0});        # 重置延迟计数
    }
  );
};

# 超时设备内容路由 - 显示所有超时设备
ajax '/ajax/content/admin/timedoutdevices' => require_role admin => sub {

  # 查询有延迟计数的设备（排除特殊设备IP 255.255.255.255）
  my @set = schema(vars->{'tenant'})->resultset('DeviceSkip')->search(
    {
      deferrals => {'>'  => 0},                    # 延迟计数大于0
      device    => {'!=' => '255.255.255.255'},    # 排除特殊设备IP
    }, {
      rows     => (setting('dns')->{max_outstanding} || 50),    # 限制结果数量
      order_by => [
        {-desc => 'deferrals'},                                 # 按延迟计数降序
        {-asc  => [qw/device backend/]}                         # 按设备和后端升序
      ]
    }
  )->hri->all;                                                  # 返回哈希引用数组

  # 处理时间戳格式（移除微秒部分）
  foreach my $row (@set) {
    next unless defined $row->{last_defer};                     # 跳过没有最后延迟时间的记录
    $row->{last_defer} =~ s/\.\d+//;                            # 移除微秒部分
  }

  # 异步解析主机名
  my $results = hostnames_resolve_async(\@set, [2]);

  content_type('text/html');

  # 渲染超时设备模板
  template 'ajax/admintask/timedoutdevices.tt', {
    results => $results                                         # 传递解析后的结果
    },
    {layout => undef};
};

true;
