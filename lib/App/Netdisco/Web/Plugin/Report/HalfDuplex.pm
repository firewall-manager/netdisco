# Netdisco 半双工模式端口报告插件
# 此模块提供半双工模式端口的检测功能，用于识别网络中运行在半双工模式的端口
package App::Netdisco::Web::Plugin::Report::HalfDuplex;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 半双工模式端口，支持CSV导出和API接口
register_report({
  category     => 'Port',                        # 端口类别
  tag          => 'halfduplex',
  label        => 'Ports in Half Duplex Mode',
  provides_csv => 1,                             # 支持CSV导出
  api_endpoint => 1,                             # 支持API接口
});

# 半双工模式端口报告路由 - 查找运行在半双工模式的端口
get '/ajax/content/report/halfduplex' => require_login sub {

  # 查询半双工模式的端口记录
  my @results
    = schema(vars->{'tenant'})->resultset('DevicePort')->columns([qw/ ip port name duplex /])->search(    # 选择端口基本信息字段
    {
      up     => 'up',                                                                                     # 端口状态为up
      duplex => {'-ilike' => 'half'}                                                                      # 双工模式包含"half"
    }, {
      '+columns' => [qw/ device.dns device.name /],                                                       # 添加设备DNS和名称字段
      join       => [qw/ device /],                                                                       # 连接设备表
      collapse   => 1,                                                                                    # 折叠重复记录
    }
    )->order_by([qw/ device.dns port /])->hri->all;                                                       # 按设备DNS和端口排序

  return unless scalar @results;                                                                          # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/halfduplex.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/halfduplex_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
