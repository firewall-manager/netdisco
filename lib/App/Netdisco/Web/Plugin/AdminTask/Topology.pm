# Netdisco 手动设备拓扑管理插件
# 此模块提供手动设备拓扑连接的管理功能，用于创建和管理设备间的连接关系
package App::Netdisco::Web::Plugin::AdminTask::Topology;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Device 'get_device';

use Try::Tiny;
use NetAddr::IP::Lite ':lower';

# 注册管理任务 - 手动设备拓扑管理，需要管理员或端口控制权限
register_admin_task({tag => 'topology', label => 'Manual Device Topology', roles => [qw/admin port_control/],});

# 参数验证函数 - 检查拓扑连接参数的有效性
sub _sanity_ok {

  # 验证第一个设备IP地址
  my $dev1 = NetAddr::IP::Lite->new(param('dev1'));
  return 0 unless ($dev1 and $dev1->addr ne '0.0.0.0');

  # 验证第二个设备IP地址
  my $dev2 = NetAddr::IP::Lite->new(param('dev2'));
  return 0 unless ($dev2 and $dev2->addr ne '0.0.0.0');

  # 验证端口参数
  return 0 unless param('port1');
  return 0 unless param('port2');

  # 防止自连接（同一设备的同一端口）
  return 0 if (($dev1->addr eq $dev2->addr) and (param('port1') eq param('port2')));

  return 1;
}

# 添加拓扑连接路由 - 创建新的设备间连接
ajax '/ajax/control/admin/topology/add' => require_any_role [qw(admin port_control)] => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 创建拓扑连接记录
  my $device = schema(vars->{'tenant'})->resultset('Topology')->create({
    dev1  => param('dev1'),     # 源设备IP
    port1 => param('port1'),    # 源端口
    dev2  => param('dev2'),     # 目标设备IP
    port2 => param('port2'),    # 目标端口
  });

  # 重新设置受影响端口的远程设备详情
  # 可能因设备或端口名称错误而失败
  try {
    schema(vars->{'tenant'})->txn_do(sub {

      # 只处理根IP设备
      my $left  = get_device(param('dev1'));    # 获取源设备
      my $right = get_device(param('dev2'));    # 获取目标设备

      # 跳过无效条目
      return unless ($left->in_storage and $right->in_storage);

      # 更新源设备端口的远程连接信息
      $left->ports->search({port => param('port1')}, {for => 'update'})->single()->update({
        remote_ip   => param('dev2'),     # 远程设备IP
        remote_port => param('port2'),    # 远程端口
        remote_type => undef,             # 清除远程类型
        remote_id   => undef,             # 清除远程ID
        is_uplink   => \"true",           # 标记为上行链路
        manual_topo => \"true",           # 标记为手动拓扑
      });

      # 更新目标设备端口的远程连接信息
      $right->ports->search({port => param('port2')}, {for => 'update'})->single()->update({
        remote_ip   => param('dev1'),     # 远程设备IP
        remote_port => param('port1'),    # 远程端口
        remote_type => undef,             # 清除远程类型
        remote_id   => undef,             # 清除远程ID
        is_uplink   => \"true",           # 标记为上行链路
        manual_topo => \"true",           # 标记为手动拓扑
      });
    });
  };
};

# 删除拓扑连接路由 - 删除现有的设备间连接
ajax '/ajax/control/admin/topology/del' => require_any_role [qw(admin port_control)] => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 在事务中删除拓扑连接记录
  schema(vars->{'tenant'})->txn_do(sub {
    my $device = schema(vars->{'tenant'})->resultset('Topology')->search({
      dev1  => param('dev1'),     # 源设备IP
      port1 => param('port1'),    # 源端口
      dev2  => param('dev2'),     # 目标设备IP
      port2 => param('port2'),    # 目标端口
    })->delete;    # 删除匹配的拓扑记录
  });

  # 重新设置受影响端口的远程设备详情
  # 可能因设备或端口名称错误而失败
  try {
    schema(vars->{'tenant'})->txn_do(sub {

      # 只处理根IP设备
      my $left  = get_device(param('dev1'));    # 获取源设备
      my $right = get_device(param('dev2'));    # 获取目标设备

      # 跳过无效条目
      return unless ($left->in_storage and $right->in_storage);

      # 清除源设备端口的远程连接信息
      $left->ports->search({port => param('port1')}, {for => 'update'})->single()->update({
        remote_ip   => undef,       # 清除远程设备IP
        remote_port => undef,       # 清除远程端口
        remote_type => undef,       # 清除远程类型
        remote_id   => undef,       # 清除远程ID
        is_uplink   => \"false",    # 取消上行链路标记
        manual_topo => \"false",    # 取消手动拓扑标记
      });

      # 清除目标设备端口的远程连接信息
      $right->ports->search({port => param('port2')}, {for => 'update'})->single()->update({
        remote_ip   => undef,       # 清除远程设备IP
        remote_port => undef,       # 清除远程端口
        remote_type => undef,       # 清除远程类型
        remote_id   => undef,       # 清除远程ID
        is_uplink   => \"false",    # 取消上行链路标记
        manual_topo => \"false",    # 取消手动拓扑标记
      });
    });
  };
};

# 拓扑内容路由 - 显示所有手动拓扑连接
ajax '/ajax/content/admin/topology' => require_any_role [qw(admin port_control)] => sub {

  # 查询所有拓扑连接，按设备1、设备2、端口1排序
  my $set = schema(vars->{'tenant'})->resultset('Topology')->search({}, {order_by => [qw/dev1 dev2 port1/]});

  content_type('text/html');

  # 渲染拓扑模板
  template 'ajax/admintask/topology.tt', {
    results => $set,    # 传递拓扑连接结果集
    },
    {layout => undef};
};

true;
