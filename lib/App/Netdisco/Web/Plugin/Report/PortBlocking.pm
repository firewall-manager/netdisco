# Netdisco 生成树阻塞端口报告插件
# 此模块提供生成树协议阻塞端口的统计功能，用于识别网络中因生成树协议而被阻塞的端口
package App::Netdisco::Web::Plugin::Report::PortBlocking;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 生成树阻塞端口，支持CSV导出和API接口
register_report({
  category     => 'Port',                      # 端口类别
  tag          => 'portblocking',
  label        => 'Blocked - Spanning Tree',
  provides_csv => 1,                           # 支持CSV导出
  api_endpoint => 1,                           # 支持API接口
});

# 生成树阻塞端口报告路由 - 查找被生成树协议阻塞的端口
get '/ajax/content/report/portblocking' => require_login sub {

  # 查询生成树阻塞的端口
  my @results = schema(vars->{'tenant'})->resultset('Device')->search(
    {
      'stp' => ['blocking', 'broken'],    # STP状态为阻塞或损坏
      'up'  => {'!=', 'down'}             # 端口状态不是down
    }, {
      select     => ['ip', 'dns', 'name'],    # 选择设备基本信息
      join       => ['ports'],                # 连接端口表
      '+columns' => [
        {'port'        => 'ports.port'},      # 端口号
        {'description' => 'ports.name'},      # 端口描述
        {'stp'         => 'ports.stp'},       # STP状态
      ]
    }
  )->hri->all;

  return unless scalar @results;    # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/portblocking.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/portblocking_csv.tt', {results => \@results,}, {layout => 'noop'};
  }
};

1;
