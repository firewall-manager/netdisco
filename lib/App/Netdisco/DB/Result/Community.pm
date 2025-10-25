use utf8;
package App::Netdisco::DB::Result::Community;

# SNMP社区字符串结果类
# 提供SNMP社区字符串和认证标签的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("community");

# 定义表列
# 包含设备IP和SNMP社区字符串信息
__PACKAGE__->add_columns(
  "ip",                  {data_type => "inet", is_nullable => 0},
  "snmp_comm_rw",        {data_type => "text", is_nullable => 1},
  "snmp_auth_tag_read",  {data_type => "text", is_nullable => 1},
  "snmp_auth_tag_write", {data_type => "text", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("ip");

1;
