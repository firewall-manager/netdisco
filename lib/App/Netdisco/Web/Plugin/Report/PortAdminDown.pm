# Netdisco 管理性关闭端口报告插件
# 此模块提供管理性关闭端口的统计功能，用于识别网络中被人为关闭的端口
package App::Netdisco::Web::Plugin::Report::PortAdminDown;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 管理性关闭端口，支持CSV导出和API接口
register_report({
  category     => 'Port',                              # 端口类别
  tag          => 'portadmindown',
  label        => 'Ports Administratively Disabled',
  provides_csv => 1,                                   # 支持CSV导出
  api_endpoint => 1,                                   # 支持API接口
});

# 管理性关闭端口报告路由 - 查找管理性关闭的端口
get '/ajax/content/report/portadmindown' => require_login sub {

  # 查询管理性关闭的端口
  my @results = schema(vars->{'tenant'})->resultset('Device')->search(
    {'up_admin' => 'down'},                            # 管理状态为down
    {
      select     => ['ip', 'dns', 'name'],             # 选择设备基本信息
      join       => ['ports'],                         # 连接端口表
      '+columns' => [
        {'port'        => 'ports.port'},               # 端口号
        {'description' => 'ports.name'},               # 端口描述
        {'up_admin'    => 'ports.up_admin'},           # 管理状态
      ]
    }
  )->hri->all;

  return unless scalar @results;    # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/portadmindown.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/portadmindown_csv.tt', {results => \@results,}, {layout => 'noop'};
  }
};

1;
