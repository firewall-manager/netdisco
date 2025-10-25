use utf8;
package App::Netdisco::DB::Result::DeviceVlan;

# 设备VLAN结果类
# 提供设备VLAN信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_vlan");

# 定义表列
# 包含设备IP、VLAN ID、描述、创建时间和最后发现时间
__PACKAGE__->add_columns(
  "ip",
  {data_type => "inet", is_nullable => 0},
  "vlan",
  {data_type => "integer", is_nullable => 0},
  "description",
  {data_type => "text", is_nullable => 1},
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
__PACKAGE__->set_primary_key("ip", "vlan");

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this VLAN entry was discovered.

=cut

# 定义关联关系：设备
# 返回发现此VLAN条目的设备表条目
__PACKAGE__->belongs_to(device => 'App::Netdisco::DB::Result::Device', 'ip');

=head2 port_vlans_tagged

Link relationship for C<tagged_ports>, see below.

=cut

# 定义关联关系：标记端口VLAN
# 支持tagged_ports的链接关系
__PACKAGE__->has_many(
  port_vlans_tagged => 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip"   => {-ident => "$args->{self_alias}.ip"},
      "$args->{foreign_alias}.vlan" => {-ident => "$args->{self_alias}.vlan"},
      -not_bool                     => "$args->{foreign_alias}.native",
    };
  },
  {cascade_copy => 0, cascade_update => 0, cascade_delete => 0}
);

=head2 port_vlans_untagged

Link relationship to support C<untagged_ports>, see below.

=cut

# 定义关联关系：未标记端口VLAN
# 支持untagged_ports的链接关系
__PACKAGE__->has_many(
  port_vlans_untagged => 'App::Netdisco::DB::Result::DevicePortVlan',
  sub {
    my $args = shift;
    return {
      "$args->{foreign_alias}.ip"   => {-ident => "$args->{self_alias}.ip"},
      "$args->{foreign_alias}.vlan" => {-ident => "$args->{self_alias}.vlan"},
      -bool                         => "$args->{foreign_alias}.native",
    };
  },
  {cascade_copy => 0, cascade_update => 0, cascade_delete => 0}
);

=head2 ports

Link relationship to support C<ports>.

=cut

# 定义关联关系：端口
# 支持ports的链接关系
__PACKAGE__->has_many(
  ports => 'App::Netdisco::DB::Result::DevicePortVlan',
  {'foreign.ip' => 'self.ip', 'foreign.vlan' => 'self.vlan'},
  {cascade_copy => 0, cascade_update => 0, cascade_delete => 0}
);

=head2 tagged_ports

Returns the set of Device Ports on which this VLAN is configured to be tagged.

=cut

# 定义关联关系：标记端口
# 返回配置此VLAN为标记的设备端口集合
__PACKAGE__->many_to_many(tagged_ports => 'port_vlans_tagged', 'port');

=head2 untagged_ports

Returns the set of Device Ports on which this VLAN is an untagged VLAN.

=cut

# 定义关联关系：未标记端口
# 返回此VLAN为未标记VLAN的设备端口集合
__PACKAGE__->many_to_many(untagged_ports => 'port_vlans_untagged', 'port');

1;
