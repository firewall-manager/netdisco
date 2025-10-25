use utf8;
package App::Netdisco::DB::Result::DeviceModule;

# 设备模块结果类
# 提供设备硬件模块信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_module");

# 定义表列
# 包含设备IP、模块索引、描述、类型、版本和序列号等信息
__PACKAGE__->add_columns(
  "ip",
  {data_type => "inet", is_nullable => 0},
  "index",
  {data_type => "integer", is_nullable => 0},
  "description",
  {data_type => "text", is_nullable => 1},
  "type",
  {data_type => "text", is_nullable => 1},
  "parent",
  {data_type => "integer", is_nullable => 1},
  "name",
  {data_type => "text", is_nullable => 1},
  "class",
  {data_type => "text", is_nullable => 1},
  "pos",
  {data_type => "integer", is_nullable => 1},
  "hw_ver",
  {data_type => "text", is_nullable => 1},
  "fw_ver",
  {data_type => "text", is_nullable => 1},
  "sw_ver",
  {data_type => "text", is_nullable => 1},
  "serial",
  {data_type => "text", is_nullable => 1},
  "model",
  {data_type => "text", is_nullable => 1},
  "fru",
  {data_type => "boolean", is_nullable => 1},
  "creation", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "last_discover",
  {data_type => "timestamp", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("ip", "index");

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this VLAN entry was discovered.

=cut

# 定义关联关系：设备
# 返回发现此VLAN条目的设备表条目
__PACKAGE__->belongs_to(device => 'App::Netdisco::DB::Result::Device', 'ip');

1;
