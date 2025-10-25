use utf8;
package App::Netdisco::DB::Result::DevicePortSsid;

# 设备端口SSID结果类
# 提供设备端口SSID信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_port_ssid");
# 定义表列
# 包含设备IP、端口、SSID、广播状态和BSSID信息
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "ssid",
  { data_type => "text", is_nullable => 1 },
  "broadcast",
  { data_type => "boolean", is_nullable => 1 },
  "bssid",
  { data_type => "macaddr", is_nullable => 0 },
);

# 设置主键
__PACKAGE__->set_primary_key("ip", "bssid", "port");


=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which hosts this SSID.

=cut

# 定义关联关系：设备
# 返回托管此SSID的设备表条目
__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 port

Returns the entry from the C<port> table which corresponds to this SSID.

=cut

# 定义关联关系：端口
# 返回与此SSID对应的端口表条目
__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
    'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 nodes

Returns the set of Nodes whose MAC addresses are associated with this Device
Port SSID.

=cut

# 定义关联关系：节点
# 返回与此设备端口SSID关联的MAC地址节点集合
__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Node',
  {
    'foreign.switch' => 'self.ip',
    'foreign.port' => 'self.port',
  },
  { join_type => 'LEFT',
    cascade_copy => 0, cascade_update => 0, cascade_delete => 0 },
);

1;
