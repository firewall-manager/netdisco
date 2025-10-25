# Netdisco 设备名称/DNS不匹配报告插件
# 此模块提供设备名称与DNS记录不匹配的检测功能，用于识别网络中DNS配置问题
package App::Netdisco::Web::Plugin::Report::DeviceDnsMismatch;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 设备名称/DNS不匹配，支持CSV导出和API接口
register_report({
  category     => 'Device',                         # 设备类别
  tag          => 'devicednsmismatch',
  label        => 'Device Name / DNS Mismatches',
  provides_csv => 1,                                # 支持CSV导出
  api_endpoint => 1,                                # 支持API接口
});

# 设备名称/DNS不匹配报告路由 - 检测设备名称与DNS记录的不匹配情况
get '/ajax/content/report/devicednsmismatch' => require_login sub {

  # 构建域名后缀模式，用于DNS匹配检查
  (my $suffix = '***:' . setting('domain_suffix')) =~ s|\Q(?^\Eu?|(?|g;

  # 查询设备名称与DNS不匹配的记录
  my @results
    = schema(vars->{'tenant'})
    ->resultset('Virtual::DeviceDnsMismatch')
    ->search(undef, {bind => [$suffix, $suffix]})                 # 绑定域名后缀参数
    ->columns([qw/ ip dns name location contact /])->hri->all;    # 选择设备基本信息字段

  return unless scalar @results;                                  # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/devicednsmismatch.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/devicednsmismatch_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
