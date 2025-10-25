use utf8;
package App::Netdisco::DB::Result::Manufacturer;

# 制造商结果类
# 提供网络设备制造商信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("manufacturer");

# 定义表列
# 包含制造商公司信息、缩写、基础、位数、MAC地址范围和范围信息
__PACKAGE__->add_columns(
  "company", {data_type => "text",      is_nullable => 1}, "abbrev", {data_type => "text",    is_nullable => 1},
  "base",    {data_type => "text",      is_nullable => 0}, "bits",   {data_type => "integer", is_nullable => 1},
  "first",   {data_type => "macaddr",   is_nullable => 1}, "last",   {data_type => "macaddr", is_nullable => 1},
  "range",   {data_type => "int8range", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("base");

1;
