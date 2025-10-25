package App::Netdisco::DB::Result::PortCtlRole;

# 端口控制角色结果类
# 提供设备端口按角色的端口控制权限管理模型

use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::PortCtlRole

=head1 DESCRIPTION

PortControl permissions for device ports by role.

=cut

__PACKAGE__->table('portctl_role');

# 定义表列
# 包含角色ID、角色名称、设备ACL ID和端口ACL ID
__PACKAGE__->add_columns(
  "id",            {data_type => "integer", is_nullable => 0, is_auto_increment => 1},
  "role_name",     {data_type => "text",    is_nullable => 0},
  "device_acl_id", {data_type => "integer", is_nullable => 0},
  "port_acl_id",   {data_type => "integer", is_nullable => 0},
);

# 设置主键
__PACKAGE__->set_primary_key("id");

# 定义关联关系：设备ACL
# 返回与此角色关联的设备访问控制列表
__PACKAGE__->belongs_to(
  device_acl => 'App::Netdisco::DB::Result::AccessControlList',
  {'foreign.id' => 'self.device_acl_id'}, {cascade_delete => 1}
);

# 定义关联关系：带DNS的设备ACL
# 返回与此角色关联的带DNS信息的设备访问控制列表
__PACKAGE__->belongs_to(
  device_acl_with_dns => 'App::Netdisco::DB::Result::Virtual::ACLEntriesWithDNS',
  {'foreign.id' => 'self.device_acl_id'}, {cascade_delete => 1}
);

# 定义关联关系：端口ACL
# 返回与此角色关联的端口访问控制列表
__PACKAGE__->belongs_to(
  port_acl => 'App::Netdisco::DB::Result::AccessControlList',
  {'foreign.id' => 'self.port_acl_id'}, {cascade_delete => 1}
);

# 定义关联关系：带DNS的端口ACL
# 返回与此角色关联的带DNS信息的端口访问控制列表
__PACKAGE__->belongs_to(
  port_acl_with_dns => 'App::Netdisco::DB::Result::Virtual::ACLEntriesWithDNS',
  {'foreign.id' => 'self.port_acl_id'}, {cascade_delete => 1}
);

1;
