use utf8;
package App::Netdisco::DB::Result::Subnet;

# 子网结果类
# 提供网络子网信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("subnets");

# 定义表列
# 包含网络CIDR、创建时间和最后发现时间
__PACKAGE__->add_columns(
  "net",
  {data_type => "cidr", is_nullable => 0},
  "creation", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "last_discover", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
);

# 设置主键
__PACKAGE__->set_primary_key("net");

1;
