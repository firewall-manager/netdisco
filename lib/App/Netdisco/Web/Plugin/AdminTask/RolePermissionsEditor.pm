# Netdisco 角色权限编辑器插件
# 此模块提供角色权限的详细编辑功能，用于管理端口控制角色的具体权限规则
package App::Netdisco::Web::Plugin::AdminTask::RolePermissionsEditor;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

use MIME::Base64 'decode_base64';

# 注册管理任务 - 角色权限编辑器（隐藏任务）
register_admin_task({
  tag    => "rolepermissionseditor",
  label  => "Role Permissions Editor",
  hidden => true,                        # 隐藏任务，不显示在管理界面中
});

# 角色权限编辑器内容路由 - 显示指定角色的权限详情
get '/ajax/content/admin/rolepermissionseditor' => require_role admin => sub {
  my $role = param('role_name');
  send_error('Bad Request', 400) unless $role;    # 验证角色名称参数

  # 查询指定角色的权限记录，预取设备ACL和端口ACL信息
  my $rows = schema(vars->{'tenant'})->resultset('PortCtlRole')->search(
    {role_name => $role},
    {
      prefetch => [qw/device_acl_with_dns port_acl/],    # 预取ACL信息
      order_by => 'me.id'                                # 按ID排序
    }
  ) or send_error('Bad Request', 400);                   # 如果角色不存在则返回错误

  # 渲染角色权限编辑器模板
  template 'ajax/admintask/rolepermissionseditor.tt', {
    role_name => $role,                                  # 角色名称
    results   => $rows,                                  # 权限记录结果集
    },
    {layout => undef};
};

# 添加角色权限路由 - 为角色添加新的权限规则
post '/ajax/control/admin/rolepermissionseditor/add' => require_role admin => sub {
  my $role        = param("role_name");                            # 角色名称
  my $device_rule = param("device_rule");                          # 设备规则
  my $port_rule   = param("port_rule");                            # 端口规则
  send_error('Bad Request', 400) unless $device_rule and $role;    # 验证必要参数

  # 在事务中创建新的权限记录
  schema(vars->{'tenant'})->txn_do(sub {

    # 创建新的端口控制角色记录
    my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')->create({
      role_name  => $role,    # 角色名称
      device_acl => {},       # 设备访问控制列表
      port_acl   => {},       # 端口访问控制列表
    });

    # 更新设备ACL规则
    $row->device_acl->update({
      rules => [$device_rule],    # 设置设备规则
    });

    # 如果提供了端口规则，则更新端口ACL
    $row->port_acl->update({
      rules => [$port_rule],      # 设置端口规则
    }) if $port_rule;
  });
};

# 删除角色权限路由 - 删除指定的权限规则
post '/ajax/control/admin/rolepermissionseditor/delete' => require_role admin => sub {
  my $id   = param("id");                                 # 记录ID
  my $role = param("role_name");                          # 角色名称
  send_error('Bad Request', 400) unless $id and $role;    # 验证参数

  # 在事务中删除权限记录
  schema(vars->{'tenant'})->txn_do(sub {

    # 查找要删除的记录
    my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')->find($id);

    # 删除相关的访问控制列表
    schema(vars->{'tenant'})->resultset('AccessControlList')->find($row->device_acl_id)->delete;    # 删除设备ACL
    schema(vars->{'tenant'})->resultset('AccessControlList')->find($row->port_acl_id)->delete;      # 删除端口ACL

    $row->delete;                                                                                   # 删除权限记录

    # 如果角色没有任何权限规则，创建默认规则
    if (schema(vars->{'tenant'})->resultset('PortCtlRole')->search({role_name => $role})->count() == 0) {

      # 角色不能为空 - 只能从端口控制角色面板删除
      my $new = schema(vars->{'tenant'})->resultset('PortCtlRole')->create({
        role_name  => $role,    # 角色名称
        device_acl => {},       # 设备ACL
        port_acl   => {},       # 端口ACL
      });

      # 设置默认设备ACL规则
      $new->device_acl->update({rules => ['group:__ANY__']});
    }
  });
};

# 更新角色权限路由 - 更新现有的权限规则
post '/ajax/control/admin/rolepermissionseditor/update' => require_role admin => sub {
  my $id   = param("id");                                 # 记录ID
  my $role = param("role_name");                          # 角色名称
  send_error('Bad Request', 400) unless $id and $role;    # 验证参数

  # 解码Base64编码的设备规则
  my @device_rules = map { decode_base64($_) } @{
    ref param('device_rule')
    ? param('device_rule')                                     # 如果是数组引用
    : defined param('device_rule') ? [param('device_rule')]    # 如果定义了单个值
    :                                []
  };    # 否则为空数组
        # 解码Base64编码的端口规则
  my @port_rules = map { decode_base64($_) } @{
    ref param('port_rule')
    ? param('port_rule')                                   # 如果是数组引用
    : defined param('port_rule') ? [param('port_rule')]    # 如果定义了单个值
    :                              []
  };    # 否则为空数组

  # 在事务中更新权限规则
  schema(vars->{'tenant'})->txn_do(sub {

    # 查找要更新的记录
    my $row = schema(vars->{'tenant'})->resultset('PortCtlRole')->find($id);

    # 更新设备ACL规则
    schema(vars->{'tenant'})
      ->resultset('AccessControlList')
      ->find($row->device_acl_id)
      ->update({rules => \@device_rules});

    # 更新端口ACL规则
    schema(vars->{'tenant'})->resultset('AccessControlList')->find($row->port_acl_id)->update({rules => \@port_rules});
  });
};

true;

