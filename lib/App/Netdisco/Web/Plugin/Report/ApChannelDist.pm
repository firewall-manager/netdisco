# Netdisco 接入点信道分布报告插件
# 此模块提供无线接入点信道分布统计功能，用于分析网络中无线信道的使用情况
package App::Netdisco::Web::Plugin::Report::ApChannelDist;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 接入点信道分布，支持CSV导出和API接口
register_report({
  category     => 'Wireless',                            # 无线类别
  tag          => 'apchanneldist',
  label        => 'Access Point Channel Distribution',
  provides_csv => 1,                                     # 支持CSV导出
  api_endpoint => 1,                                     # 支持API接口
});

# 接入点信道分布报告路由 - 统计各信道的使用数量
get '/ajax/content/report/apchanneldist' => require_login sub {

  # 查询无线端口信道分布统计
  my @results = schema(vars->{'tenant'})->resultset('DevicePortWireless')->search(
    {channel => {'!=', '0'}},                            # 排除信道为0的记录
    {
      select   => ['channel', {count => 'channel'}],     # 选择信道和计数
      as       => [qw/ channel ch_count /],              # 字段别名
      group_by => [qw/channel/],                         # 按信道分组
      order_by => {-desc => [qw/count/]},                # 按计数降序排列
    },
  )->hri->all;

  return unless scalar @results;                         # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/apchanneldist.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/apchanneldist_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
