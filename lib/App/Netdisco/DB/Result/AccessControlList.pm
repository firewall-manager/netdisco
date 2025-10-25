package App::Netdisco::DB::Result::AccessControlList;

# 访问控制列表结果类
# 提供数据库中的ACL模型

use utf8;
use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

=head1 NAME

App::Netdisco::DB::Result::AccessControlList

=head1 DESCRIPTION

Models an ACL in the database.

=cut

__PACKAGE__->table('access_control_list');

# 定义表列
# 包含ACL的ID、名称和规则数组
__PACKAGE__->add_columns(
  "id",       {data_type => "integer", is_nullable => 0, is_auto_increment => 1},
  "acl_name", {data_type => "text",    is_nullable => 1},
  "rules",    {data_type => "text[]",  is_nullable => 0},
);

# 设置主键
__PACKAGE__->set_primary_key("id");

1;
