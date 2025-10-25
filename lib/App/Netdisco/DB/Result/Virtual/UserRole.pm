use utf8;
package App::Netdisco::DB::Result::Virtual::UserRole;

# 用户角色虚拟结果类
# 提供用户角色权限信息的虚拟视图

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->table_class('DBIx::Class::ResultSource::View');

__PACKAGE__->table("user_role");
__PACKAGE__->result_source_instance->is_virtual(1);
# 虚拟视图定义：用户角色
# 聚合用户的各种角色权限，包括本地权限和认证方式
__PACKAGE__->result_source_instance->view_definition(<<ENDSQL
  SELECT username, 'port_control' AS role FROM users
    WHERE port_control
  UNION
  SELECT username, 'admin' AS role FROM users
    WHERE admin
  UNION
  SELECT username, 'ldap' AS role FROM users
    WHERE ldap
  UNION
  SELECT username, 'radius' AS role FROM users
    WHERE radius
  UNION
  SELECT username, 'tacacs' AS role FROM users
    WHERE tacacs
  UNION
  SELECT username, 'api' AS role FROM users
    WHERE ( ? ::boolean = false ) OR
          ( token IS NOT NULL AND token_from IS NOT NULL
          AND token_from > (EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - ?) )
  UNION
  SELECT username, 'api_admin' AS role FROM users
    WHERE admin AND (( ? ::boolean = false ) OR
          ( token IS NOT NULL AND token_from IS NOT NULL
          AND token_from > (EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) - ?) ))
ENDSQL
);

# 定义虚拟视图的列
# 包含用户名和角色信息
__PACKAGE__->add_columns(
  'username' => { data_type => 'text' },
  'role' => { data_type => 'text' },
);

1;
