# Netdisco 用户管理插件
# 此模块提供用户账户的管理功能，包括用户的创建、删除、更新和权限管理
package App::Netdisco::Web::Plugin::AdminTask::Users;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Passphrase;

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::Port 'sync_portctl_roles';
use List::MoreUtils 'uniq';
use Digest::MD5 ();

# 注册管理任务 - 用户管理，支持CSV导出
register_admin_task({tag => 'users', label => 'User Management', provides_csv => 1,});

# 参数验证函数 - 检查用户名参数的有效性
sub _sanity_ok {
  return 0 unless param('username')                 # 必须有用户名参数
    and param('username') =~ m/^[[:print:] ]+$/;    # 且用户名只包含可打印字符和空格
  return 1;
}

# 密码生成函数 - 根据配置生成安全的密码哈希
sub _make_password {
  my $pass = (shift || passphrase->generate_random);    # 使用提供的密码或生成随机密码
  if (setting('safe_password_store')) {

    # 如果启用了安全密码存储，使用passphrase生成
    return passphrase($pass)->generate;
  }
  else {
    # 否则使用MD5哈希（不推荐，但为了向后兼容）
    return Digest::MD5::md5_hex($pass),;
  }
}

# 添加用户路由 - 创建新的用户账户
ajax '/ajax/control/admin/users/add' => require_role setting('defanged_admin') => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 在事务中创建新用户
  schema(vars->{'tenant'})->txn_do(sub {
    my $user = schema(vars->{'tenant'})->resultset('User')->create({
      username => param('username'),                    # 用户名
      password => _make_password(param('password')),    # 密码（哈希后）
      fullname => param('fullname'),                    # 全名

      # 根据认证方法设置相应的认证标志
      (
        param('auth_method')
        ? (
          (ldap => (param('auth_method') eq 'ldap' ? \'true' : \'false')),        # LDAP认证
          (radius => (param('auth_method') eq 'radius' ? \'true' : \'false')),    # RADIUS认证
          (tacacs => (param('auth_method') eq 'tacacs' ? \'true' : \'false')),    # TACACS认证
          )
        : (
          ldap   => \'false',                                                     # 默认禁用LDAP
          radius => \'false',                                                     # 默认禁用RADIUS
          tacacs => \'false',                                                     # 默认禁用TACACS
        )
      ),

      port_control => (param('port_control')                                           ? \'true' : \'false'),   # 端口控制权限
      portctl_role => ((param('port_control') and param('port_control') ne '_global_') ? param('port_control') : '')
      ,                                                                                                         # 端口控制角色

      admin => (param('admin') ? \'true' : \'false'),                                                           # 管理员权限
      note  => param('note'),                                                                                   # 备注
    });
  });
};

# 删除用户路由 - 删除指定的用户账户
ajax '/ajax/control/admin/users/del' => require_role setting('defanged_admin') => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 在事务中删除用户
  schema(vars->{'tenant'})->txn_do(sub {
    schema(vars->{'tenant'})->resultset('User')->find({username => param('username')})->delete;    # 根据用户名查找并删除
  });
};

# 更新用户路由 - 更新现有用户的信息
ajax '/ajax/control/admin/users/update' => require_role setting('defanged_admin') => sub {
  send_error('Bad Request', 400) unless _sanity_ok();    # 验证参数

  # 在事务中更新用户信息
  schema(vars->{'tenant'})->txn_do(sub {
    my $user = schema(vars->{'tenant'})->resultset('User')->find({username => param('username')});    # 查找用户
    return unless $user;                                                                              # 如果用户不存在则返回

    # 更新用户信息
    $user->update({

      # 只有在密码不是占位符时才更新密码
      ((param('password') ne '********') ? (password => _make_password(param('password'))) : ()),
      fullname => param('fullname'),    # 全名

      # 根据认证方法设置相应的认证标志
      (
        param('auth_method')
        ? (
          (ldap => (param('auth_method') eq 'ldap' ? \'true' : \'false')),        # LDAP认证
          (radius => (param('auth_method') eq 'radius' ? \'true' : \'false')),    # RADIUS认证
          (tacacs => (param('auth_method') eq 'tacacs' ? \'true' : \'false')),    # TACACS认证
          )
        : (
          ldap   => \'false',                                                     # 默认禁用LDAP
          radius => \'false',                                                     # 默认禁用RADIUS
          tacacs => \'false',                                                     # 默认禁用TACACS
        )
      ),

      port_control => (param('port_control')                                           ? \'true' : \'false'),   # 端口控制权限
      portctl_role => ((param('port_control') and param('port_control') ne '_global_') ? param('port_control') : '')
      ,                                                                                                         # 端口控制角色

      admin => (param('admin') ? \'true' : \'false'),                                                           # 管理员权限
      note  => param('note'),                                                                                   # 备注
    });
  });
};

# 用户内容路由 - 显示所有用户信息
get '/ajax/content/admin/users' => require_role admin => sub {

  # 查询所有用户，包含格式化的时间字段
  my @results = schema(vars->{'tenant'})->resultset('User')->search(
    undef, {
      '+columns' => {
        created   => \"to_char(creation, 'YYYY-MM-DD HH24:MI')",    # 创建时间（格式化）
        last_seen => \"to_char(last_on,  'YYYY-MM-DD HH24:MI')",    # 最后登录时间（格式化）
      },
      order_by => [qw/fullname username/]                           # 按全名和用户名排序
    }
  )->hri->all;

  return unless scalar @results;                                    # 如果没有结果则返回

  # 同步端口控制角色
  sync_portctl_roles();

  # 获取端口控制角色列表
  my @port_control_roles = keys %{setting('portctl_by_role') || {}};                           # 从配置获取
  push @port_control_roles, schema(vars->{'tenant'})->resultset('PortCtlRole')->role_names;    # 从数据库获取

  # 根据请求类型返回不同格式的数据
  if (request->is_ajax) {

    # AJAX请求：返回HTML模板
    template 'ajax/admintask/users.tt', {
      results            => \@results,                                       # 用户结果集
      port_control_roles => [uniq sort { $a cmp $b } @port_control_roles]    # 去重排序的端口控制角色
      },
      {layout => undef};
  }
  else {
    # 非AJAX请求：返回CSV格式数据
    header('Content-Type' => 'text/comma-separated-values');
    template 'ajax/admintask/users_csv.tt', {results => \@results,}, {layout => undef};
  }
};

true;
