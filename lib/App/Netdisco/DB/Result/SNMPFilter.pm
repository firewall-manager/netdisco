use utf8;
package App::Netdisco::DB::Result::SNMPFilter;

# SNMP过滤器结果类
# 提供SNMP对象过滤器信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("snmp_filter");
# 定义表列
# 包含叶子节点和子名称信息
__PACKAGE__->add_columns(
  "leaf",
  { data_type => "text", is_nullable => 0 },
  "subname",
  { data_type => "text", is_nullable => 0 },
);

# 设置主键
__PACKAGE__->set_primary_key("leaf");

1;
