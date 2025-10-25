use utf8;
package App::Netdisco::DB::Result::DevicePortVlan;

# 设备端口VLAN结果类
# 提供设备端口VLAN配置信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_port_vlan");

# 定义表列
# 包含设备IP、端口、VLAN ID、原生状态、出口标记和VLAN类型
__PACKAGE__->add_columns(
  "ip",
  {data_type => "inet", is_nullable => 0},
  "port",
  {data_type => "text", is_nullable => 0},
  "vlan",
  {data_type => "integer", is_nullable => 0},
  "native",
  {data_type => "boolean", default_value => \"false", is_nullable => 0},
  "egress_tag",
  {data_type => "boolean", default_value => \"true", is_nullable => 0},
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
  "vlantype",
  {data_type => "text", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("ip", "port", "vlan", "native");

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which hosts the Port on which this
VLAN is configured.

=cut

# 定义关联关系：设备
# 返回托管此VLAN配置端口的设备表条目
__PACKAGE__->belongs_to(device => 'App::Netdisco::DB::Result::Device', 'ip');

=head2 port

Returns the entry from the C<port> table on which this VLAN is configured.

=cut

# 定义关联关系：端口
# 返回配置此VLAN的端口表条目
__PACKAGE__->belongs_to(
  port => 'App::Netdisco::DB::Result::DevicePort',
  {'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',}
);

=head2 vlan_entry

Returns the entry from the C<device_vlan> table describing this VLAN in
detail, typically in order that the C<name> can be retrieved.

=cut

# 定义关联关系：VLAN条目
# 返回详细描述此VLAN的device_vlan表条目，通常用于检索VLAN名称
__PACKAGE__->belongs_to(
  vlan_entry => 'App::Netdisco::DB::Result::DeviceVlan',
  {'foreign.ip' => 'self.ip', 'foreign.vlan' => 'self.vlan',}
);

1;
