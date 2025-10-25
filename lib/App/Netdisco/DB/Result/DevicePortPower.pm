use utf8;
package App::Netdisco::DB::Result::DevicePortPower;

# 设备端口功率结果类
# 提供设备端口PoE功率信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_port_power");
# 定义表列
# 包含设备IP、端口、模块、管理状态、功率状态和功率等级
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "port",
  { data_type => "text", is_nullable => 0 },
  "module",
  { data_type => "integer", is_nullable => 1 },
  "admin",
  { data_type => "text", is_nullable => 1 },
  "status",
  { data_type => "text", is_nullable => 1 },
  "class",
  { data_type => "text", is_nullable => 1 },
  "power",
  { data_type => "integer", is_nullable => 1 },
);

# 设置主键
__PACKAGE__->set_primary_key("port", "ip");



=head1 RELATIONSHIPS

=head2 port

Returns the entry from the C<port> table for which this Power entry applies.

=cut

# 定义关联关系：端口
# 返回此功率条目适用的端口表条目
__PACKAGE__->belongs_to( port => 'App::Netdisco::DB::Result::DevicePort', {
  'foreign.ip' => 'self.ip', 'foreign.port' => 'self.port',
});

=head2 device_module

Returns the entry from the C<device_power> table for which this Power entry
applies.

=cut

# 定义关联关系：设备模块
# 返回此功率条目适用的device_power表条目
__PACKAGE__->belongs_to( device_module => 'App::Netdisco::DB::Result::DevicePower', {
  'foreign.ip' => 'self.ip', 'foreign.module' => 'self.module',
});

1;
