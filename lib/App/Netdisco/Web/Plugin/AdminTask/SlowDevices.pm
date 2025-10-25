# Netdisco 慢设备管理插件
# 此模块提供慢设备检测功能，用于识别轮询速度较慢的设备
package App::Netdisco::Web::Plugin::AdminTask::SlowDevices;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 慢设备检测
register_admin_task({tag => 'slowdevices', label => 'Slowest Devices',});

# 慢设备内容路由 - 显示轮询速度最慢的设备
ajax '/ajax/content/admin/slowdevices' => require_role admin => sub {

  # 查询慢设备虚拟结果集
  my $set = schema(vars->{'tenant'})->resultset('Virtual::SlowDevices');

  content_type('text/html');

  # 渲染慢设备模板
  template 'ajax/admintask/slowdevices.tt', {
    results => $set,    # 传递慢设备结果集
    },
    {layout => undef};
};

true;
