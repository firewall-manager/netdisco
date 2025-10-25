# Netdisco 设备地址管理插件
# 此模块提供设备接口地址的查看和导出功能
package App::Netdisco::Web::Plugin::Device::Addresses;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册设备标签页 - 地址管理页面，支持CSV导出
register_device_tab({tag => 'addresses', label => 'Addresses', provides_csv => 1});

# 设备接口地址查询路由 - 需要用户登录
get '/ajax/content/device/addresses' => require_login sub {

  # 获取查询参数中的设备标识
  my $q = param('q');

  # 根据设备标识查找设备，如果找不到则返回错误
  my $device = schema(vars->{'tenant'})->resultset('Device')->search_for_device($q) or send_error('Bad device', 400);

  # 获取设备的所有IP地址，按别名排序并预加载端口信息
  my @results = $device->device_ips->search({}, {order_by => 'alias', prefetch => 'device_port'})->hri->all;

  # 如果没有结果则直接返回
  return unless scalar @results;

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/device/addresses.tt', {results => $json}, {layout => undef};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/device/addresses_csv.tt', {results => \@results}, {layout => undef};
  }
};

1;
