# Netdisco 双工模式不匹配报告插件
# 此模块提供端口双工模式不匹配的检测功能，用于识别网络中双工配置不一致的端口
package App::Netdisco::Web::Plugin::Report::DuplexMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 双工模式不匹配，支持CSV导出和API接口
register_report({
  category     => 'Port',                # 端口类别
  tag          => 'duplexmismatch',
  label        => 'Mismatched Duplex',
  provides_csv => 1,                     # 支持CSV导出
  api_endpoint => 1,                     # 支持API接口
});

# 双工模式不匹配报告路由 - 检测端口双工模式不匹配的情况
get '/ajax/content/report/duplexmismatch' => require_login sub {

  # 查询双工模式不匹配的端口记录
  my @results = schema(vars->{'tenant'})->resultset('Virtual::DuplexMismatch')->hri->all;

  return unless scalar @results;    # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/duplexmismatch.tt', {results => $json,}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/duplexmismatch_csv.tt', {results => \@results,}, {layout => 'noop'};
  }
};

1;
