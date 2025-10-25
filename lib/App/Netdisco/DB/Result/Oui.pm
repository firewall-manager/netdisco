use utf8;
package App::Netdisco::DB::Result::Oui;

# OUI结果类
# 提供网络设备OUI信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("oui");

# 定义表列
# 包含OUI标识符、公司名称和缩写信息
__PACKAGE__->add_columns(
  "oui",     {data_type => "varchar", is_nullable => 0, size => 8},
  "company", {data_type => "text",    is_nullable => 1},
  "abbrev",  {data_type => "text",    is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("oui");

1;
