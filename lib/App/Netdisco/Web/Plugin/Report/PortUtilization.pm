# Netdisco 端口利用率报告插件
# 此模块提供端口利用率统计功能，用于分析网络中端口的使用情况和空闲状态
package App::Netdisco::Web::Plugin::Report::PortUtilization;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 端口利用率，支持CSV导出和API接口，包含时间参数
register_report({
  category       => 'Device',             # 设备类别
  tag            => 'portutilization',
  label          => 'Port Utilization',
  provides_csv   => 1,                    # 支持CSV导出
  api_endpoint   => 1,                    # 支持API接口
  api_parameters => [                     # API参数定义
    age_num => {
      description => 'Mark as Free if down for (quantity)',    # 标记为空闲的时间数量
      enum        => [1 .. 31],                                # 1-31天
      default     => '3',                                      # 默认3
    },
    age_unit => {
      description => 'Mark as Free if down for (period)',      # 标记为空闲的时间单位
      enum        => [qw/days weeks months years/],            # 天、周、月、年
      default     => 'months',                                 # 默认月
    },
  ],
});

# 端口利用率报告路由 - 显示端口利用率统计信息
get '/ajax/content/report/portutilization' => require_login sub {

  # 检查是否有设备数据
  return unless schema(vars->{'tenant'})->resultset('Device')->count;

  # 获取时间参数
  my $age_num  = param('age_num')  || 3;           # 时间数量，默认3
  my $age_unit = param('age_unit') || 'months';    # 时间单位，默认月

  # 查询端口利用率数据
  my @results
    = schema(vars->{'tenant'})
    ->resultset('Virtual::PortUtilization')
    ->search(undef, {bind => ["$age_num $age_unit", "$age_num $age_unit", "$age_num $age_unit"]})
    ->hri->all;                                    # 绑定时间参数

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/portutilization.tt', {results => $json}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/portutilization_csv.tt', {results => \@results,}, {layout => 'noop'};
  }
};

1;
