# Netdisco 端口SSID清单报告插件
# 此模块提供端口SSID清单统计功能，用于分析网络中无线端口的SSID配置情况
package App::Netdisco::Web::Plugin::Report::PortSsid;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 端口SSID清单，支持CSV导出和API接口，包含SSID参数
register_report({
  category       => 'Port',                  # 端口类别
  tag            => 'portssid',
  label          => 'Port SSID Inventory',
  provides_csv   => 1,                       # 支持CSV导出
  api_endpoint   => 1,                       # 支持API接口
  api_parameters => [                        # API参数定义
    ssid => {
      description => 'Get details for this SSID',    # 获取指定SSID的详细信息
    },
  ],
});

# 模板前钩子 - 处理搜索侧边栏模板的选中项
hook 'before_template' => sub {
  my $tokens = shift;

  # 只对端口SSID相关路径生效
  return
    unless (request->path eq uri_for('/report/portssid')->path
    or index(request->path, uri_for('/ajax/content/report/portssid')->path) == 0);

  # 用于在搜索侧边栏模板中设置选中项
  foreach my $opt (qw/ssid/) {
    my $p = (
      ref [] eq ref param($opt)               # 检查参数是否为数组引用
      ? param($opt)
      : (param($opt) ? [param($opt)] : [])    # 转换为数组引用
    );
    $tokens->{"${opt}_lkp"} = {map { $_ => 1 } @$p};    # 创建查找哈希
  }
};

# 端口SSID内容路由 - 显示端口SSID清单信息
get '/ajax/content/report/portssid' => require_login sub {

  # 获取SSID参数
  my $ssid = param('ssid');

  # 获取设备端口SSID结果集
  my $rs = schema(vars->{'tenant'})->resultset('DevicePortSsid');

  # 如果指定了SSID，查询该SSID的详细信息
  if (defined $ssid) {

    # 按SSID搜索并连接相关表
    $rs = $rs->search(
      {ssid => $ssid},    # 按SSID过滤
      {
        '+columns' => [
          qw/ device.dns device.name device.model device.vendor port.port/    # 添加设备DNS、名称、型号、厂商和端口信息
        ],
        join     => [qw/ device port /],                                      # 连接设备和端口表
        collapse => 1,                                                        # 折叠重复记录
      }
    )->order_by([qw/ port.ip port.port /])->hri;                              # 按端口IP和端口号排序
  }
  else {
    # 如果没有指定SSID，获取所有SSID列表
    $rs = $rs->get_ssids->hri;
  }

  my @results = $rs->all;
  return unless scalar @results;    # 如果没有结果则返回

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回JSON格式的HTML模板
    my $json = to_json(\@results);
    template 'ajax/report/portssid.tt', {results => $json, opt => $ssid}, {layout => 'noop'};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/report/portssid_csv.tt', {results => \@results, opt => $ssid}, {layout => 'noop'};
  }
};

1;
