# Netdisco 子网利用率报告插件
# 此模块提供子网利用率统计功能，用于分析网络中IP子网的使用情况和利用率
package App::Netdisco::Web::Plugin::Report::SubnetUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;
use POSIX qw/strftime/;

# 注册报告 - 子网利用率，支持CSV导出和API接口，包含多个API参数
register_report({
  category       => 'IP',                   # IP类别
  tag            => 'subnets',
  label          => 'Subnet Utilization',
  provides_csv   => 1,                      # 支持CSV导出
  api_endpoint   => 1,                      # 支持API接口
  api_parameters => [                       # API参数定义
    subnet => {
      description => 'IP Prefix to search',    # 要搜索的IP前缀
      default     => '0.0.0.0/32',             # 默认值
    },
    daterange => {
      description => 'Date range to search',                               # 要搜索的日期范围
      default     => ('1970-01-01 to ' . strftime('%Y-%m-%d', gmtime)),    # 默认日期范围
    },
    age_invert => {
      description => 'Results should NOT be within daterange',             # 结果不应在日期范围内
      type        => 'boolean',
      default     => 'false',                                              # 年龄反转选项
    },
  ],
});

# 子网利用率报告路由 - 显示子网利用率统计信息
get '/ajax/content/report/subnets' => require_login sub {

  # 获取子网参数
  my $subnet = param('subnet')     || '0.0.0.0/32';    # 默认子网
  my $agenot = param('age_invert') || '0';             # 年龄反转参数

  # 处理日期范围参数
  my $daterange = param('daterange') || ('1970-01-01 to ' . strftime('%Y-%m-%d', gmtime));
  my ($start, $end) = $daterange =~ /(\d+-\d+-\d+)/gmx;    # 提取开始和结束日期
  $start = $start . ' 00:00:00';                           # 开始时间设为当天开始
  $end   = $end . ' 23:59:59';                             # 结束时间设为当天结束

  # 查询子网利用率数据
  my @results = schema(vars->{'tenant'})->resultset('Virtual::SubnetUtilization')->search(
    undef, {
      # 绑定参数：子网、开始时间、结束时间、开始时间、子网、开始时间、开始时间
      bind => [$subnet, $start, $end, $start, $subnet, $start, $start],
    }
  )->hri->all;

  return unless scalar @results;                           # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回HTML模板
    template 'ajax/report/subnets.tt', {results => \@results}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/subnets_csv.tt', {results => \@results}, {layout => 'noop'};
  }
};

1;
