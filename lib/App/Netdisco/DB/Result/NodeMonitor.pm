use utf8;
package App::Netdisco::DB::Result::NodeMonitor;

# 节点监控结果类
# 提供网络节点监控信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("node_monitor");

# 定义表列
# 包含MAC地址、OUI匹配、活跃状态、原因、国家代码和日期信息
__PACKAGE__->add_columns(
  "mac",
  {data_type => "macaddr", is_nullable => 0},
  "matchoui",
  {data_type => "boolean", is_nullable => 1},
  "active",
  {data_type => "boolean", is_nullable => 1},
  "why",
  {data_type => "text", is_nullable => 1},
  "cc",
  {data_type => "text", is_nullable => 1},
  "date", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
);

# 设置主键
__PACKAGE__->set_primary_key("mac");

1;
