# Netdisco 节点监控管理插件
# 此模块提供节点监控功能，用于管理需要特殊监控的MAC地址
package App::Netdisco::Web::Plugin::AdminTask::NodeMonitor;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Node 'check_mac';

# 注册管理任务 - 节点监控管理
register_admin_task({tag => 'nodemonitor', label => 'Node Monitor',});

# MAC地址验证函数 - 检查MAC地址格式是否正确
sub _sanity_ok {
  return 0 unless param('mac')      # 必须有MAC参数
    and check_mac(param('mac'));    # 且MAC格式正确

  params->{mac} = check_mac(param('mac'));    # 标准化MAC地址格式
  return 1;
}

# 添加节点监控路由 - 创建新的节点监控记录
ajax '/ajax/control/admin/nodemonitor/add' => require_role admin => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证MAC地址

  # 在事务中创建监控记录
  schema(vars->{'tenant'})->txn_do(sub {
    my $monitor = schema(vars->{'tenant'})->resultset('NodeMonitor')->create({
      mac      => param('mac'),                                # MAC地址
      matchoui => (param('matchoui') ? \'true' : \'false'),    # 是否匹配OUI
      active   => (param('active')   ? \'true' : \'false'),    # 是否激活
      why      => param('why'),                                # 监控原因
      cc       => param('cc'),                                 # 抄送邮箱
    });
  });
};

# 删除节点监控路由 - 删除指定的节点监控记录
ajax '/ajax/control/admin/nodemonitor/del' => require_role admin => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证MAC地址

  # 在事务中删除监控记录
  schema(vars->{'tenant'})->txn_do(sub {
    schema(vars->{'tenant'})->resultset('NodeMonitor')->find({mac => param('mac')})->delete;    # 根据MAC地址查找并删除
  });
};

# 更新节点监控路由 - 更新现有的节点监控记录
ajax '/ajax/control/admin/nodemonitor/update' => require_role admin => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证MAC地址

  # 在事务中更新监控记录
  schema(vars->{'tenant'})->txn_do(sub {
    my $monitor = schema(vars->{'tenant'})->resultset('NodeMonitor')->find({mac => param('mac')});    # 查找现有记录
    return unless $monitor;                                                                           # 如果记录不存在则返回

    # 更新监控记录的所有字段
    $monitor->update({
      mac      => param('mac'),                                # MAC地址
      matchoui => (param('matchoui') ? \'true' : \'false'),    # 是否匹配OUI
      active   => (param('active')   ? \'true' : \'false'),    # 是否激活
      why      => param('why'),                                # 监控原因
      cc       => param('cc'),                                 # 抄送邮箱
      date     => \'LOCALTIMESTAMP',                           # 更新时间戳
    });
  });
};

# 节点监控内容路由 - 显示所有节点监控记录
ajax '/ajax/content/admin/nodemonitor' => require_role admin => sub {

  # 查询所有节点监控记录，按激活状态、日期和MAC地址排序
  my $set = schema(vars->{'tenant'})->resultset('NodeMonitor')->search(undef, {order_by => [qw/active date mac/]});

  content_type('text/html');

  # 渲染节点监控模板
  template 'ajax/admintask/nodemonitor.tt', {
    results => $set,    # 传递监控记录结果集
    },
    {layout => undef};
};

true;
