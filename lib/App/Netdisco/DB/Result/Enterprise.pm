use utf8;
package App::Netdisco::DB::Result::Enterprise;

# 企业号结果类
# 提供SNMP企业号信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("enterprise");

# 定义表列
# 包含企业号和对应的组织名称
__PACKAGE__->add_columns(
  "enterprise_number",
  { data_type => "integer", is_nullable => 0 },
  "organization",
  { data_type => "text", is_nullable => 0 },
);

# 设置主键
__PACKAGE__->set_primary_key("enterprise_number");

1;
