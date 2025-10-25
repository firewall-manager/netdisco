use utf8;
package App::Netdisco::DB::Result::User;

# 用户结果类
# 提供用户账户信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("users");

# 定义表列
# 包含用户名、密码、令牌、认证方式、权限和用户信息
__PACKAGE__->add_columns(
  "username",
  {data_type => "varchar", is_nullable => 0, size => 50},
  "password",
  {data_type => "text", is_nullable => 1},
  "token",
  {data_type => "text", is_nullable => 1},
  "token_from",
  {data_type => "integer", is_nullable => 1},
  "creation", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "last_on",
  {data_type => "timestamp", is_nullable => 1},
  "port_control",
  {data_type => "boolean", default_value => \"false", is_nullable => 1},
  "portctl_role",
  {data_type => "text", is_nullable => 1},
  "ldap",
  {data_type => "boolean", default_value => \"false", is_nullable => 1},
  "radius",
  {data_type => "boolean", default_value => \"false", is_nullable => 1},
  "tacacs",
  {data_type => "boolean", default_value => \"false", is_nullable => 1},
  "admin",
  {data_type => "boolean", default_value => \"false", is_nullable => 1},
  "fullname",
  {data_type => "text", is_nullable => 1},
  "note",
  {data_type => "text", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("username");

# 定义关联关系：角色
# 返回与此用户关联的角色集合
__PACKAGE__->has_many(
  roles => 'App::Netdisco::DB::Result::Virtual::UserRole',
  'username', {cascade_copy => 0, cascade_update => 0, cascade_delete => 0}
);

# 创建时间方法
# 返回用户创建时间
sub created { return (shift)->get_column('created') }

# 最后访问时间方法
# 返回用户最后访问时间
sub last_seen { return (shift)->get_column('last_seen') }

1;
