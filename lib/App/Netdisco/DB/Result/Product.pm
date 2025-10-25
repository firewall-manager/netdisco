use utf8;
package App::Netdisco::DB::Result::Product;

# 产品结果类
# 提供网络设备产品信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("product");

# 定义表列
# 包含OID、MIB、叶子节点和描述信息
__PACKAGE__->add_columns(
  "oid",  {data_type => "text", is_nullable => 0}, "mib",   {data_type => "text", is_nullable => 0},
  "leaf", {data_type => "text", is_nullable => 0}, "descr", {data_type => "text", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("oid");

1;
