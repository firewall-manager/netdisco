package App::Netdisco::Web::PortControl;

# 端口控制Web模块
# 提供网络端口控制功能

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use App::Netdisco::JobQueue qw/jq_insert jq_userlog/;

# 端口控制AJAX路由
# 处理端口控制操作请求
ajax '/ajax/portcontrol' => require_any_role [qw(admin port_control)] => sub {
    send_error('No device/port/field', 400)
      unless param('device') and (param('port') or param('field'));

    # 构建日志消息
    my $log = sprintf 'd:[%s] p:[%s] f:[%s]. a:[%s] v[%s]',
      param('device'), (param('port') || ''), param('field'),
      (param('action') || ''), (param('value') || '');

    # 动作映射表
    my %action_map = (
      'location' => 'location',
      'contact'  => 'contact',
      'c_port'   => 'portcontrol',
      'c_name'   => 'portname',
      'c_pvid'   => 'vlan',
      'c_power'  => 'power',
    );

    # 确定动作和子动作
    my $action = ($action_map{ param('field') } || param('field') || '');
    my $subaction = ($action =~ m/^(?:power|portcontrol)/
      ? (param('action') ."-other")
      : param('value'));

    # 在数据库事务中处理端口控制
    schema(vars->{'tenant'})->txn_do(sub {
      # 如果有端口参数，记录端口日志
      if (param('port')) {
          my $act = "$action $subaction";
          $act =~ s/-other$//;
          $act =~ s/^portcontrol/port/;
          $act =~ s/^device_port_custom_field_/custom_field: /;

          schema(vars->{'tenant'})->resultset('DevicePortLog')->create({
            ip => param('device'),
            port => param('port'),
            action => $act,
            username => session('logged_in_user'),
            userip => request->remote_address,
            reason => (param('reason') || 'other'),
            log => param('log'),
          });
      }

      # 插入作业到队列
      jq_insert({
        device => param('device'),
        port => param('port'),
        action => $action,
        subaction => $subaction,
        username => session('logged_in_user'),
        userip => request->remote_address,
        log => $log,
      });
    });

    content_type('application/json');
    to_json({});
};

# 用户日志AJAX路由
# 获取用户作业日志
ajax '/ajax/userlog' => require_login sub {
    my @jobs = jq_userlog( session('logged_in_user') );

    # 按状态分类作业
    my %status = (
      'done' => [
        map  {s/\[\]/&lt;empty&gt;/; $_}
        map  { $_->log }
        grep { $_->status eq 'done' }
        grep { defined }
        @jobs
      ],
      'error' => [
        map  {s/\[\]/&lt;empty&gt;/; $_}
        map  { $_->log }
        grep { $_->status eq 'error' }
        grep { defined }
        @jobs
      ],
    );

    content_type('application/json');
    to_json(\%status);
};

true;
