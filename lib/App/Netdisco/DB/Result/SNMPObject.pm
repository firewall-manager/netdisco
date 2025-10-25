use utf8;
package App::Netdisco::DB::Result::SNMPObject;

# SNMP对象结果类
# 提供SNMP对象信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("snmp_object");
# 定义表列
# 包含OID、MIB、类型、访问权限、索引、状态和描述信息
__PACKAGE__->add_columns(
  "oid",
  { data_type => "text", is_nullable => 0 },
  "oid_parts",
  { data_type => "integer[]", is_nullable => 0 },
  "mib",
  { data_type => "text", is_nullable => 0 },
  "leaf",
  { data_type => "text", is_nullable => 0 },
  "type",
  { data_type => "text", is_nullable => 1 },
  "access",
  { data_type => "text", is_nullable => 1 },
  "index",
  { data_type => "text[]", is_nullable => 1, default_value => \"'{}'::text[]" },
  "num_children",
  { data_type => "integer", is_nullable => 0, default_value => \'0' },
  "status",
  { data_type => "text", is_nullable => 1 },
  "enum",
  { data_type => "text[]", is_nullable => 1, default_value => \"'{}'::text[]" },
  "descr",
  { data_type => "text", is_nullable => 1 },
);

# 设置主键
__PACKAGE__->set_primary_key("oid");

# 定义关联关系：设备浏览器
# 返回与此SNMP对象关联的设备浏览器条目（如果存在）
__PACKAGE__->might_have( device_browser => 'App::Netdisco::DB::Result::DeviceBrowser', 'oid' );

# 定义关联关系：SNMP过滤器
# 返回与此SNMP对象关联的SNMP过滤器条目（如果存在）
__PACKAGE__->might_have( snmp_filter => 'App::Netdisco::DB::Result::SNMPFilter', { 'foreign.leaf' => 'self.leaf' } );

1;
