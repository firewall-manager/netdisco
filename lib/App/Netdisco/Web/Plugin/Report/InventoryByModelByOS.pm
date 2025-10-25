# Netdisco 按型号和操作系统分组的设备清单报告插件
# 此模块提供按设备型号和操作系统分组的设备清单统计功能，用于分析网络中设备的型号和操作系统分布
package App::Netdisco::Web::Plugin::Report::InventoryByModelByOS;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 按型号和操作系统分组的设备清单，不支持CSV导出
register_report({
  category     => 'Device',                     # 设备类别
  tag          => 'inventorybymodelbyos',
  label        => 'Inventory by Model by OS',
  provides_csv => 0,                            # 不支持CSV导出
});

# 按型号和操作系统分组的设备清单报告路由 - 统计各型号和操作系统的设备数量
get '/ajax/content/report/inventorybymodelbyos' => require_login sub {

  # 查询设备型号和操作系统统计
  my @results = schema(vars->{'tenant'})->resultset('Device')->search(
    undef, {
      columns  => [qw/vendor model os os_ver/],                         # 选择厂商、型号、操作系统、版本字段
      select   => [{count => 'os_ver'}],                                # 计算操作系统版本数量
      as       => [qw/ os_ver_count /],                                 # 字段别名
      group_by => [qw/ vendor model os os_ver /],                       # 按厂商、型号、操作系统、版本分组
      order_by => ['vendor', 'model', {-desc => 'count'}, 'os_ver'],    # 按厂商、型号、计数降序、版本排序
    }
  )->hri->all;

  # 渲染按型号和操作系统分组的设备清单模板
  template 'ajax/report/inventorybymodelbyos.tt', {results => \@results,}, {layout => undef};
};

1;
