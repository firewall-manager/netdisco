# Netdisco 轮询器性能管理插件
# 此模块提供轮询器性能监控功能，用于分析设备轮询的性能数据
package App::Netdisco::Web::Plugin::AdminTask::PollerPerformance;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 轮询器性能监控
register_admin_task({
  tag => 'performance',
  label => 'Poller Performance',
});

# 轮询器性能内容路由 - 显示轮询器性能数据
ajax '/ajax/content/admin/performance' => require_role admin => sub {
    # 查询轮询器性能虚拟结果集
    my $set = schema(vars->{'tenant'})->resultset('Virtual::PollerPerformance');

    content_type('text/html');
    # 渲染轮询器性能模板
    template 'ajax/admintask/performance.tt', {
      results => $set,  # 传递性能数据结果集
    }, { layout => undef };
};

true;
