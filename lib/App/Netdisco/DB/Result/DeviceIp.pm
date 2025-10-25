use utf8;
package App::Netdisco::DB::Result::DeviceIp;

# 设备IP别名结果类
# 提供设备IP别名和接口信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';

__PACKAGE__->table("device_ip");
# 定义表列
# 包含设备IP、别名、子网、端口和DNS信息
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "alias",
  { data_type => "inet", is_nullable => 0 },
  "subnet",
  { data_type => "cidr", is_nullable => 1 },
  "port",
  { data_type => "text", is_nullable => 1 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "creation",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
);

# 设置主键
__PACKAGE__->set_primary_key("ip", "alias");



=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table to which this IP alias relates.

=cut

# 定义关联关系：设备
# 返回此IP别名关联的设备表条目
__PACKAGE__->belongs_to( device => 'App::Netdisco::DB::Result::Device', 'ip' );

=head2 device_port

Returns the Port on which this IP address is configured (typically a loopback,
routed port or virtual interface).

=cut

# 定义关联关系：设备端口
# 返回此IP地址配置的端口（通常是回环、路由端口或虚拟接口）
__PACKAGE__->belongs_to( device_port => 'App::Netdisco::DB::Result::DevicePort',
  { 'foreign.port' => 'self.port', 'foreign.ip' => 'self.ip' } );

1;
