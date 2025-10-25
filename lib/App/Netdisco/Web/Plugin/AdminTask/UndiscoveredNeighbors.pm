# Netdisco 未发现邻居管理插件
# 此模块提供未发现邻居设备的检测功能，用于识别网络中未被发现的设备
package App::Netdisco::Web::Plugin::AdminTask::UndiscoveredNeighbors;

use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::Device qw/is_discoverable/;

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 未发现邻居检测，支持CSV导出
register_admin_task({tag => 'undiscoveredneighbors', label => 'Undiscovered Neighbors', provides_csv => 1,});

# 注意此查询的问题：
# 使用DeviceSkip表来查看发现是否被阻止，但该表只显示
# 在不被允许的后端上被阻止的操作，所以可能有一个运行中的后端
# 允许该操作，我们无法知道。

# 未发现邻居内容路由 - 显示所有未发现的邻居设备
get '/ajax/content/admin/undiscoveredneighbors' => require_role admin => sub {

  # 查询未发现邻居虚拟结果集
  my @results = schema(vars->{'tenant'})->resultset('Virtual::UndiscoveredNeighbors')->hri->all;
  return unless scalar @results;    # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回HTML模板
    template 'ajax/admintask/undiscoveredneighbors.tt', {results => \@results,}, {layout => undef};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/admintask/undiscoveredneighbors_csv.tt', {results => \@results,}, {layout => undef};
  }
};

1;
