use utf8;
package App::Netdisco::DB::Result::DevicePortWireless;

# 设备端口无线结果类
# 提供设备端口无线接口信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_port_wireless");

# 定义表列
# 包含设备IP、端口、无线频道和功率信息
__PACKAGE__->add_columns(
  "ip",      {data_type => "inet",    is_nullable => 0}, "port",  {data_type => "text",    is_nullable => 0},
  "channel", {data_type => "integer", is_nullable => 1}, "power", {data_type => "integer", is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("port", "ip");

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table which hosts this wireless port.

=cut

# 定义关联关系：设备
# 返回托管此无线端口的设备表条目
__PACKAGE__->belongs_to(device => 'App::Netdisco::DB::Result::Device', 'ip');

=head2 port

Returns the entry from the C<port> table which corresponds to this wireless
interface.

=cut

# 定义关联关系：端口
# 返回与此无线接口对应的端口表条目
__PACKAGE__->belongs_to(
  port => 'App::Netdisco::DB::Result::DevicePort',
  {'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',}
);

=head2 nodes

Returns the set of Nodes whose MAC addresses are associated with this Device
Port Wireless.

=cut

# 定义关联关系：节点
# 返回与此设备端口无线接口关联的MAC地址节点集合
__PACKAGE__->has_many(
  nodes => 'App::Netdisco::DB::Result::Node',
  {'foreign.switch' => 'self.ip', 'foreign.port' => 'self.port',},
  {join_type => 'LEFT', cascade_copy => 0, cascade_update => 0, cascade_delete => 0},
);

1;
