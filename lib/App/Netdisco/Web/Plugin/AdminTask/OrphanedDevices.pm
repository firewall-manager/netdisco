# Netdisco 孤立设备管理插件
# 此模块提供孤立设备和网络检测功能，用于识别网络中的孤立设备
package App::Netdisco::Web::Plugin::AdminTask::OrphanedDevices;

use strict;
use warnings;
use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 孤立设备/网络检测，支持CSV导出
register_admin_task({tag => 'orphaned', label => 'Orphaned Devices / Networks', provides_csv => 1,});

# 孤立设备内容路由 - 检测和显示网络中的孤立设备
get '/ajax/content/admin/orphaned' => require_role admin => sub {

  # 查询网络拓扑边聚合数据（无向边）
  my @tree
    = schema(vars->{'tenant'})
    ->resultset('Virtual::UnDirEdgesAgg')
    ->search(undef, {prefetch => 'device'})
    ->hri->all;    # 预取设备信息

  # 查询孤立设备记录
  my @orphans
    = schema(vars->{'tenant'})->resultset('Virtual::OrphanedDevices')->search()->order_by('ip')->hri->all;    # 按IP地址排序

  # 如果没有拓扑数据或孤立设备，则返回
  return unless (scalar @tree || scalar @orphans);

  my @ordered;                                                                                                # 有序的图数据

  # 如果有拓扑数据，进行图分析
  if (scalar @tree) {

    # 构建节点到边的映射
    my %tree = map { $_->{'left_ip'} => $_ } @tree;

    my $current_graph = 0;     # 当前图编号
    my %visited       = ();    # 已访问的节点
    my @to_visit      = ();    # 待访问的节点队列

    # 遍历所有节点，进行连通分量分析
    foreach my $node (keys %tree) {
      next if exists $visited{$node};    # 跳过已访问的节点

      $current_graph++;                  # 新的连通分量
      @to_visit = ($node);               # 从当前节点开始

      # 广度优先搜索遍历连通分量
      while (@to_visit) {
        my $node_to_visit = shift @to_visit;    # 取出队列中的节点

        $visited{$node_to_visit} = $current_graph;    # 标记为已访问

        # 将未访问的邻居节点加入队列
        push @to_visit, grep { !exists $visited{$_} } @{$tree{$node_to_visit}->{'links'}};
      }
    }

    # 按连通分量组织设备
    my @graphs = ();
    foreach my $key (keys %visited) {
      push @{$graphs[$visited{$key} - 1]}, $tree{$key}->{'device'};
    }

    # 按设备数量降序排列图（大的连通分量在前）
    @ordered = sort { scalar @{$b} <=> scalar @{$a} } @graphs;
  }

  # 如果图数量少于2且没有拓扑数据，则返回
  return if (scalar @ordered < 2 && !scalar @tree);

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回HTML模板
    template 'ajax/admintask/orphaned.tt', {
      orphans => \@orphans,    # 孤立设备列表
      graphs  => \@ordered,    # 连通分量列表
      },
      {layout => undef};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/admintask/orphaned_csv.tt', {
      orphans => \@orphans,    # 孤立设备列表
      graphs  => \@ordered,    # 连通分量列表
      },
      {layout => undef};
  }
};

1;
