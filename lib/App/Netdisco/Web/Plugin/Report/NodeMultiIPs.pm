# Netdisco 多IP地址节点报告插件
# 此模块提供具有多个活跃IP地址的节点统计功能，用于识别网络中具有多个IP地址的节点
package App::Netdisco::Web::Plugin::Report::NodeMultiIPs;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 多IP地址节点，支持CSV导出和API接口
register_report({
  category     => 'Node',                                      # 节点类别
  tag          => 'nodemultiips',
  label        => 'Nodes with multiple active IP addresses',
  provides_csv => 1,                                           # 支持CSV导出
  api_endpoint => 1,                                           # 支持API接口
});

# 多IP地址节点报告路由 - 查找具有多个活跃IP地址的节点
get '/ajax/content/report/nodemultiips' => require_login sub {

  # 查询具有多个IP地址的节点
  my @results = schema(vars->{'tenant'})->resultset('Node')->search(
    {},
    {
      select     => ['mac', 'switch', 'port'],        # 选择节点基本信息
      join       => [qw/device ips manufacturer/],    # 连接设备、IP和制造商表
      '+columns' => [
        {'dns'      => 'device.dns'},                 # 设备DNS名称
        {'name'     => 'device.name'},                # 设备名称
        {'ip_count' => {count => 'ips.ip'}},          # IP地址数量统计
        {'vendor'   => 'manufacturer.company'}        # 制造商公司
      ],
      group_by => [
        qw/ me.mac me.switch me.port device.dns device.name manufacturer.company/    # 按节点和设备信息分组
      ],
      having   => \['count(ips.ip) > ?', [count => 1]],                              # 过滤：IP数量大于1
      order_by => {-desc => [qw/count/]},                                            # 按计数降序排列
    }
  )->hri->all;

  return unless scalar @results;                                                     # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/nodemultiips.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/nodemultiips_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
