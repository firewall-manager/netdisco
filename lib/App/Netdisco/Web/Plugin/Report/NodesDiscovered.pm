# Netdisco 通过LLDP/CDP发现的节点报告插件
# 此模块提供通过LLDP/CDP协议发现的节点统计功能，用于分析网络中通过邻居发现协议发现的设备
package App::Netdisco::Web::Plugin::Report::NodesDiscovered;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Web 'sql_match';

# 注册报告 - 通过LLDP/CDP发现的节点，支持CSV导出和API接口，包含多个API参数
register_report({
  category       => 'Node',                                # 节点类别
  tag            => 'nodesdiscovered',
  label          => 'Nodes discovered through LLDP/CDP',
  provides_csv   => 1,                                     # 支持CSV导出
  api_endpoint   => 1,                                     # 支持API接口
  api_parameters => [                                      # API参数定义
    remote_id => {
      description => 'Host Name reported',                 # 报告的主机名
    },
    remote_type => {
      description => 'Platform reported',                  # 报告的平台
    },
    aps => {
      description => 'Include Wireless APs in the report',    # 在报告中包含无线接入点
      type        => 'boolean',
      default     => 'false',
    },
    phones => {
      description => 'Include IP Phones in the report',       # 在报告中包含IP电话
      type        => 'boolean',
      default     => 'false',
    },
    matchall => {
      description => 'Match all parameters (true) or any (false)',    # 匹配所有参数或任一参数
      type        => 'boolean',
      default     => 'false',
    },
  ],
});

# 通过LLDP/CDP发现的节点报告路由 - 查找通过邻居发现协议发现的节点
get '/ajax/content/report/nodesdiscovered' => require_login sub {

  # 根据matchall参数确定逻辑操作符（AND或OR）
  my $op = param('matchall') ? '-and' : '-or';

  # 查询通过LLDP/CDP发现的节点
  my @results = schema(vars->{'tenant'})->resultset('Virtual::NodesDiscovered')->search({
    $op => [

      # 如果指定了AP参数，过滤无线接入点
      (param('aps') ? ('me.remote_type' => {-ilike => 'AP:%'}) : ()),

      # 如果指定了电话参数，过滤IP电话
      (param('phones') ? ('me.remote_type' => {-ilike => '%ip_phone%'}) : ()),

      # 如果指定了远程ID参数，进行模糊匹配
      (param('remote_id') ? ('me.remote_id' => {-ilike => scalar sql_match(param('remote_id'))}) : ()),

      # 如果指定了远程类型参数，进行类型匹配
      (
        param('remote_type')
        ? (
          '-or' => [
            map  { ('me.remote_type' => {-ilike => scalar sql_match($_)}) }
            grep {$_} (ref param('remote_type') ? @{param('remote_type')} : param('remote_type'))
          ]
          )
        : ()
      ),
    ],
  })->hri->all;

  return unless scalar @results;    # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/nodesdiscovered.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/nodesdiscovered_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
