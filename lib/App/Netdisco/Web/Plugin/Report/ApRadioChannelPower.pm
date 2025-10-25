# Netdisco 接入点无线电信道和功率报告插件
# 此模块提供无线接入点无线电信道和功率统计功能，用于分析无线设备的信道配置和功率设置
package App::Netdisco::Web::Plugin::Report::ApRadioChannelPower;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use App::Netdisco::Util::ExpandParams 'expand_hash';

use App::Netdisco::Web::Plugin;

# 注册报告 - 接入点无线电信道和功率，支持CSV导出和API接口
register_report({
  category     => 'Wireless',                                # 无线类别
  tag          => 'apradiochannelpower',
  label        => 'Access Point Radios Channel and Power',
  provides_csv => 1,                                         # 支持CSV导出
  api_endpoint => 1,                                         # 支持API接口
});

# 接入点无线电数据路由 - 提供DataTables格式的无线电数据
get '/ajax/content/report/apradiochannelpower/data' => require_login sub {

  # 验证DataTables必需的draw参数
  send_error('Missing parameter', 400) unless (param('draw') && param('draw') =~ /\d+/);

  # 获取接入点无线电虚拟结果集
  my $rs = schema(vars->{'tenant'})->resultset('Virtual::ApRadioChannelPower');

  # 展开参数（用于DataTables处理）
  my $exp_params = expand_hash(scalar params);

  # 获取总记录数
  my $recordsTotal = $rs->count;

  # 获取过滤后的数据
  my @data = $rs->get_datatables_data($exp_params)->hri->all;

  # 获取过滤后的记录数
  my $recordsFiltered = $rs->get_datatables_filtered_count($exp_params);

  content_type 'application/json';

  # 返回DataTables格式的JSON数据
  return to_json({
    draw            => int(param('draw')),       # DataTables请求标识
    recordsTotal    => int($recordsTotal),       # 总记录数
    recordsFiltered => int($recordsFiltered),    # 过滤后记录数
    data            => \@data,                   # 数据数组
  });
};

# 接入点无线电内容路由 - 显示接入点无线电信道和功率信息
get '/ajax/content/report/apradiochannelpower' => require_login sub {

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回HTML模板
    template 'ajax/report/apradiochannelpower.tt', {}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    my @results = schema(vars->{'tenant'})->resultset('Virtual::ApRadioChannelPower')->hri->all;

    return unless scalar @results;    # 如果没有结果则返回

    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/apradiochannelpower_csv.tt', {results => \@results,}, {layout => 'noop'};
  }
};

1;
