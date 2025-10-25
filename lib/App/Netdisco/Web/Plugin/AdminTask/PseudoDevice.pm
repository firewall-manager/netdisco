# Netdisco 伪设备管理插件
# 此模块提供伪设备的管理功能，用于创建和管理虚拟设备
package App::Netdisco::Web::Plugin::AdminTask::PseudoDevice;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Util::DNS 'hostname_from_ip';
use App::Netdisco::Util::Statistics 'pretty_version';
use App::Netdisco::Web::Plugin;
use NetAddr::IP::Lite ':lower';

# 注册管理任务 - 伪设备管理
register_admin_task({tag => 'pseudodevice', label => 'Pseudo Devices',});

# 参数验证函数 - 检查伪设备参数的有效性
sub _sanity_ok {

  # 验证设备名称：必须存在、可打印且不包含空格
  return 0 unless param('name') and param('name') =~ m/^[[:print:]]+$/ and param('name') !~ m/[[:space:]]/;

  # 验证IP地址：必须是有效的IP地址且不是0.0.0.0
  my $ip = NetAddr::IP::Lite->new(param('ip'));
  return 0 unless ($ip and $ip->addr ne '0.0.0.0');

  # 验证端口数量：必须是数字
  return 0 unless param('ports') and param('ports') =~ m/^[[:digit:]]+$/;

  return 1;
}

# 添加伪设备路由 - 创建新的伪设备
ajax '/ajax/control/admin/pseudodevice/add' => require_role admin => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 在事务中创建伪设备
  schema(vars->{'tenant'})->txn_do(sub {

    # 创建设备记录
    my $device = schema(vars->{'tenant'})->resultset('Device')->create({
      ip            => param('ip'),                                   # IP地址
      dns           => (hostname_from_ip(param('ip')) || ''),         # DNS名称（如果可解析）
      name          => param('name'),                                 # 设备名称
      vendor        => 'netdisco',                                    # 厂商（固定为netdisco）
      model         => 'pseudodevice',                                # 型号（固定为pseudodevice）
      num_ports     => param('ports'),                                # 端口数量
      os            => 'netdisco',                                    # 操作系统（固定为netdisco）
      os_ver        => pretty_version($App::Netdisco::VERSION, 3),    # 版本信息
      layers        => param('layers'),                               # OSI层
      last_discover => \'LOCALTIMESTAMP',                             # 最后发现时间
      is_pseudo     => \'true',                                       # 标记为伪设备
    });
    return unless $device;                                            # 如果创建失败则返回

    # 创建端口记录
    $device->ports->populate([
      [qw/port type descr/],                                             # 端口字段：端口号、类型、描述
      map { ["Port$_", 'other', "Port$_"] } @{[1 .. param('ports')]},    # 生成端口1到指定数量
    ]);

    # 创建设备IP记录，用于拓扑显示
    schema(vars->{'tenant'})->resultset('DeviceIp')->create({
      ip    => param('ip'),                                              # IP地址
      alias => param('ip'),                                              # 别名（与IP相同）
    });
  });
};

# 更新伪设备路由 - 更新现有伪设备的配置
ajax '/ajax/control/admin/pseudodevice/update' => require_role admin => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 在事务中更新伪设备
  schema(vars->{'tenant'})->txn_do(sub {

    # 查找现有设备并获取端口数量
    my $device = schema(vars->{'tenant'})->resultset('Device')->with_port_count->find({ip => param('ip')});
    return unless $device;              # 如果设备不存在则返回
    my $count = $device->port_count;    # 当前端口数量

    # 如果新端口数量大于当前数量，添加新端口
    if (param('ports') > $count) {
      my $start = $count + 1;           # 新端口的起始编号
      $device->ports->populate([
        [qw/port type descr/],                                                  # 端口字段
        map { ["Port$_", 'other', "Port$_"] } @{[$start .. param('ports')]},    # 生成新端口
      ]);
    }

    # 如果新端口数量小于当前数量，删除多余端口
    elsif (param('ports') < $count) {
      my $start = param('ports') + 1;    # 要删除的端口起始编号

      # 删除多余的端口
      foreach my $port ($start .. $count) {
        $device->ports->single({port => "Port${port}"})->delete;    # 删除端口记录

        # 清除过时的手动拓扑链接
        schema(vars->{'tenant'})->resultset('Topology')->search({
          -or => [
            {dev1 => $device->ip, port1 => "Port${port}"},    # 作为源设备的链接
            {dev2 => $device->ip, port2 => "Port${port}"},    # 作为目标设备的链接
          ],
        })->delete;
      }
    }

    # 更新端口数量
    $device->update({num_ports => param('ports')});

    # 更新OSI层信息
    $device->update({layers => param('layers')});

    # 更新最后发现时间（因为设备属性已更改）
    $device->update({last_discover => \'LOCALTIMESTAMP'});
  });
};

# 伪设备内容路由 - 显示所有伪设备
ajax '/ajax/content/admin/pseudodevice' => require_role admin => sub {

  # 查询所有伪设备，按最后发现时间降序排列，包含端口数量信息
  my $set = schema(vars->{'tenant'})->resultset('Device')->search(
    {-bool    => 'is_pseudo'},                   # 只查询伪设备
    {order_by => {-desc => 'last_discover'}},    # 按最后发现时间降序
  )->with_port_count;                            # 包含端口数量信息

  content_type('text/html');

  # 渲染伪设备模板
  template 'ajax/admintask/pseudodevice.tt', {
    results => $set,                             # 传递伪设备结果集
    },
    {layout => undef};
};

true;
