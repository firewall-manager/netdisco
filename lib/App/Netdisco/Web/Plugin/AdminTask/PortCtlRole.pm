# Netdisco 端口控制角色管理插件
# 此模块提供端口控制角色的管理功能，包括角色的创建、删除和更新
package App::Netdisco::Web::Plugin::AdminTask::PortCtlRole;

use Dancer ':syntax';
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::Ajax;

use App::Netdisco::Web::Plugin;

# 注册管理任务 - 端口控制角色管理
register_admin_task({
    tag => "portctlrole",
    label => "Port Control Roles"
});

# 端口控制角色内容路由 - 显示所有端口控制角色
ajax '/ajax/content/admin/portctlrole' => require_role admin => sub {
    # 获取所有端口控制角色名称
    my @roles = schema(vars->{'tenant'})->resultset('PortCtlRole')
                                        ->role_names;

    # 渲染端口控制角色模板，按名称排序
    template 'ajax/admintask/portctlrole.tt', {
      results => [sort @roles],
    }, { layout => undef };
};

# 添加端口控制角色路由 - 创建新的端口控制角色
ajax '/ajax/control/admin/portctlrole/add' => require_role admin => sub {
    my $role = param('role_name');
    send_error('Bad Request', 400) unless $role;  # 验证角色名称参数
    
    # 检查角色是否已存在
    send_error('Bad Request', 400)
      if schema(vars->{'tenant'})->resultset('PortCtlRole')
                                 ->search({role_name => $role})->count();

    # 在事务中创建新角色
    schema(vars->{'tenant'})->txn_do(sub {
      my $new = schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->create({
          role_name => $role,           # 角色名称
          device_acl => {},             # 设备访问控制列表
          port_acl => {},               # 端口访问控制列表
        });
      # 设置默认设备ACL规则为允许所有组
      $new->device_acl->update({ rules => ['group:__ANY__'] });
    });
};

# 删除端口控制角色路由 - 删除指定的端口控制角色
ajax '/ajax/control/admin/portctlrole/delete' => require_role admin => sub {
    my $role = param('role_name');
    send_error('Bad Request', 400) unless $role;  # 验证角色名称参数

    # 在事务中删除角色及其相关数据
    schema(vars->{'tenant'})->txn_do(sub {
      my $rows = schema(vars->{'tenant'})->resultset('PortCtlRole')
                                         ->search({ role_name => $role })
        or return;  # 如果角色不存在则返回

      # 删除相关的访问控制列表
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->search({id => { -in => [ $rows->device_acls ] }})->delete;  # 删除设备ACL
      schema(vars->{'tenant'})->resultset('AccessControlList')
        ->search({id => { -in => [ $rows->port_acls ] }})->delete;    # 删除端口ACL

      $rows->delete;  # 删除角色记录

      # 更新使用该角色的用户
      schema(vars->{'tenant'})->resultset('User')
        ->search({portctl_role => $role})
        ->update({
          # 如果角色在配置中存在，则保留；否则清除端口控制权限
          ((exists config->{'portctl_by_role_shadow'}->{$role})
            ? () : (portctl_role => undef, port_control => \'false')),
        });
    });
};

# 更新端口控制角色路由 - 重命名端口控制角色
ajax '/ajax/control/admin/portctlrole/update' => require_role admin => sub {
    my $role = param('role_name');           # 新角色名称
    my $old_role = param('old-role_name');   # 原角色名称
    send_error('Bad Request', 400) unless $role and $old_role;  # 验证参数

    # 在事务中更新角色名称
    schema(vars->{'tenant'})->txn_do(sub {
      # 更新角色表中的角色名称
      schema(vars->{'tenant'})->resultset('PortCtlRole')
        ->search({ role_name => $old_role })
        ->update({ role_name => $role });

      # 更新用户表中使用该角色的用户
      schema(vars->{'tenant'})->resultset('User')
        ->search({ portctl_role => $old_role })
        ->update({ portctl_role => $role });
    });
};

true;

