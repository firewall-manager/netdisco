# Netdisco 端口控制日志报告插件
# 此模块提供端口控制日志的查看和添加功能，用于记录和查看端口的控制操作历史
package App::Netdisco::Web::Plugin::Report::PortLog;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::Web::Plugin;

# 注册报告 - 端口控制日志，隐藏报告
register_report({
  tag      => 'portlog',
  label    => 'Port Control Log',
  category => 'Port',               # 端口类别（未使用）
  hidden   => true,                 # 隐藏报告
});

# 参数验证函数 - 检查输入参数的有效性
sub _sanity_ok {
  return 0 unless param('ip') =~ m/^[[:print:]]+$/     # IP参数必须是可打印字符
    and param('port')         =~ m/^[[:print:]]+$/     # 端口参数必须是可打印字符
    and param('log')          =~ m/^[[:print:]]+$/;    # 日志参数必须是可打印字符

  return 1;
}

# 添加端口控制日志AJAX路由 - 添加新的端口控制日志记录
ajax '/ajax/control/report/portlog/add' => require_login sub {

  # 验证参数有效性
  send_error('Bad Request', 400) unless _sanity_ok();

  # 在事务中创建端口控制日志记录
  schema(vars->{'tenant'})->txn_do(sub {
    my $user = schema(vars->{'tenant'})->resultset('DevicePortLog')->create({
      ip       => param('ip'),                  # 设备IP
      port     => param('port'),                # 端口号
      reason   => 'other',                      # 原因：其他
      log      => param('log'),                 # 日志内容
      username => session('logged_in_user'),    # 登录用户名
      userip   => request->remote_address,      # 用户IP地址
      action   => 'comment',                    # 操作：评论
    });
  });
};

# 端口控制日志内容AJAX路由 - 显示指定端口的控制日志
ajax '/ajax/content/report/portlog' => require_login sub {

  # 获取设备和端口参数
  my $device = param('q');
  my $port   = param('f');
  send_error('Bad Request', 400) unless $device and $port;

  # 查找设备
  $device = schema(vars->{'tenant'})->resultset('Device')->search_for_device($device);
  return unless $device;

  # 查询端口控制日志记录
  my $set = schema(vars->{'tenant'})->resultset('DevicePortLog')->search(
    {
      ip   => $device->ip,    # 设备IP
      port => $port,          # 端口号
    }, {
      order_by => {-desc => [qw/creation/]},    # 按创建时间降序排列
      rows     => 200,                          # 限制200条记录
    }
  )->with_times;                                # 包含时间信息

  content_type('text/html');

  # 渲染端口控制日志模板
  template 'ajax/report/portlog.tt', {results => $set,}, {layout => 'noop'};
};

true;
