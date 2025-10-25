package App::Netdisco::Web::Device;

# 设备Web模块
# 提供设备信息显示和管理功能

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;

use URI ();
use URL::Encode 'url_params_mixed';
use App::Netdisco::Util::Device 'match_to_setting';
use App::Netdisco::Util::Port 'sync_portctl_roles';
use App::Netdisco::Util::Web 'request_is_device';

# 为端口连接的节点和设备构建视图设置
set('connected_properties' => [
  sort { $a->{idx} <=> $b->{idx} }
  map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
  grep { $_ =~ m/^n_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} }
]);

# 设置端口显示属性
set('port_display_properties' => [
  sort { $a->{idx} <=> $b->{idx} }
  map  {{ name => $_, %{ setting('sidebar_defaults')->{'device_ports'}->{$_} } }}
  grep { $_ =~ m/^p_/ } keys %{ setting('sidebar_defaults')->{'device_ports'} }
]);

# 加载和缓存设备端口控制配置
hook 'before' => sub {
  return unless request_is_device;
  sync_portctl_roles();
};

# 模板前钩子
hook 'before_template' => sub {
  my $tokens = shift;

  my $defaults = var('sidebar_defaults')->{'device_ports'}
    or return;

  # 用cookie设置覆盖端口表单默认值
  # 总是这样做，以便嵌入到设备端口页面的链接具有用户偏好
  if (param('reset')) {
    cookie('nd_ports-form' => '', expires => '-1 day');
  }
  elsif (my $cookie = cookie('nd_ports-form')) {
    my $cdata = url_params_mixed($cookie);

    if ($cdata and (ref {} eq ref $cdata)) {
      foreach my $key (keys %{ $defaults }) {
        $defaults->{$key} = $cdata->{$key};
      }
    }
  }

  # 用于设备搜索侧边栏模板中设置选中项
  foreach my $opt (qw/hgroup lgroup/) {
      my $p = (ref [] eq ref param($opt) ? param($opt)
                                          : (param($opt) ? [param($opt)] : []));
      $tokens->{"${opt}_lkp"} = { map { $_ => 1 } @$p };
  }

  return if param('reset')
    or not var('sidebar_key') or (var('sidebar_key') ne 'device_ports');

  # 从我们刚刚在表单提交中接收的参数更新cookie
  my $uri = URI->new();
  foreach my $key (keys %{ $defaults }) {
    $uri->query_param($key => param($key));
  }
  cookie('nd_ports-form' => $uri->query(), expires => '365 days');
};

# 设备页面路由
get '/device' => require_login sub {
    my $q = param('q');
    my $devices = schema(vars->{'tenant'})->resultset('Device');

    # 我们传递的是dns或ip
    my $dev = $devices->search({
        -or => [
            \[ 'host(me.ip) = ?' => [ bind_value => $q ] ],
            'me.dns' => $q,
        ],
    });

    if ($dev->count == 0) {
        return redirect uri_for('/', {nosuchdevice => 1, device => $q})->path_query;
    }

    # 如果传递了dns，需要检查重复项
    # 如果有重复项，只使用ip作为q参数
    my $first = $dev->first;
    my $others = ($devices->search({dns => $first->dns})->count() - 1);

    params->{'tab'} ||= 'details';
    template 'device', {
      netdisco_device => $first,
      display_name => ($others ? $first->ip : ($first->dns || $first->ip)),
      device_count => schema(vars->{'tenant'})->resultset('Device')->count(),
      lgroup_list => [ schema(vars->{'tenant'})->resultset('Device')->get_distinct_col('location') ],
      hgroup_list => setting('host_group_displaynames'),
      device => params->{'tab'},
    }, { layout => 'main' };
};

true;
