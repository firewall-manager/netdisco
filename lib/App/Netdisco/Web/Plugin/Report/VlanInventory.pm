# Netdisco VLAN清单报告插件
# 此模块提供VLAN清单统计功能，用于分析网络中VLAN的配置和使用情况
package App::Netdisco::Web::Plugin::Report::VlanInventory;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - VLAN清单，支持CSV导出和API接口
register_report({
  category     => 'VLAN',             # VLAN类别
  tag          => 'vlaninventory',
  label        => 'VLAN Inventory',
  provides_csv => 1,                  # 支持CSV导出
  api_endpoint => 1,                  # 支持API接口
});

# VLAN清单报告路由 - 显示VLAN清单信息
get '/ajax/content/report/vlaninventory' => require_login sub {

  # 查询VLAN清单数据
  my @results = schema(vars->{'tenant'})->resultset('DeviceVlan')->search(
    {
      'me.description' => {'!=', 'NULL'},    # 描述不为空
      'me.vlan'        => {'>' => 0},        # VLAN ID大于0
      'ports.vlan'     => {'>' => 0},        # 端口VLAN ID大于0
    }, {
      join   => {'ports' => 'vlan_entry'},    # 连接端口和VLAN条目表
      select => [
        'me.vlan',                            # VLAN ID
        'me.description',                     # VLAN描述
        {count => {distinct => 'me.ip'}},     # 设备数量统计
        {count => 'ports.vlan'}               # 端口数量统计
      ],
      as       => [qw/ vlan description dcount pcount /],    # 字段别名
      group_by => [qw/ me.vlan me.description /],            # 按VLAN ID和描述分组
    }
  )->hri->all;

  return unless scalar @results;                             # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/vlaninventory.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/vlaninventory_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

# 注册报告 - 多名称VLAN，支持CSV导出和API接口
register_report({
  category     => 'VLAN',                        # VLAN类别
  tag          => 'vlanmultiplenames',
  label        => 'VLANs With Multiple Names',
  provides_csv => 1,                             # 支持CSV导出
  api_endpoint => 1,                             # 支持API接口
});

# 多名称VLAN报告路由 - 显示具有多个名称的VLAN
get '/ajax/content/report/vlanmultiplenames' => require_login sub {

  # 查询具有多个名称的VLAN
  my @results = schema(vars->{'tenant'})->resultset('DeviceVlan')->search(
    {
      'me.description' => {'!=', 'NULL'},    # 描述不为空
      'me.vlan'        => {'>' => 0},        # VLAN ID大于0
      'ports.vlan'     => {'>' => 0},        # 端口VLAN ID大于0
    }, {
      join   => {'ports' => 'vlan_entry'},    # 连接端口和VLAN条目表
      select => [
        'me.vlan',                                                           # VLAN ID
        {count => {distinct => 'me.ip'}},                                    # 设备数量统计
        {count => 'ports.vlan'},                                             # 端口数量统计
        \q{ array_agg(DISTINCT me.description ORDER BY me.description) },    # 聚合所有不同的描述
      ],
      as       => [qw/ vlan dcount pcount description /],                    # 字段别名
      group_by => [qw/ me.vlan /],                                           # 按VLAN ID分组
      having   => \q{ count (DISTINCT me.description) > 1 },                 # 过滤：描述数量大于1
    }
  )->hri->all;

  return unless scalar @results;                                             # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/vlanmultiplenames.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/vlanmultiplenames.tt', {results => \@results}, {layout => 'noop'};
  }
};

true;
