# Netdisco 设备VLAN管理插件
# 此模块提供设备VLAN信息的查看和导出功能
package App::Netdisco::Web::Plugin::Device::Vlans;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册设备标签页 - VLAN管理页面，支持CSV导出
register_device_tab({tag => 'vlans', label => 'VLANs', provides_csv => 1});

# 设备VLAN信息查询路由 - 需要用户登录
get '/ajax/content/device/vlans' => require_login sub {

  # 获取查询参数中的设备标识
  my $q = param('q');

  # 根据设备标识查找设备，如果找不到则返回错误
  my $device = schema(vars->{'tenant'})->resultset('Device')->search_for_device($q) or send_error('Bad device', 400);

  # 获取设备的VLAN信息，过滤掉VLAN 0，按VLAN ID排序
  my @results = $device->vlans->search({vlan => {'>' => 0}}, {order_by => 'vlan'})->hri->all;

  # 如果没有结果则直接返回
  return unless scalar @results;

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/device/vlans.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/device/vlans_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

true;
