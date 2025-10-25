use utf8;
package App::Netdisco::DB::Result::DevicePower;

# 设备功率结果类
# 提供设备功率模块信息的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_power");

# 定义表列
# 包含设备IP、模块索引、功率值和状态信息
__PACKAGE__->add_columns(
  "ip",    {data_type => "inet",    is_nullable => 0}, "module", {data_type => "integer", is_nullable => 0},
  "power", {data_type => "integer", is_nullable => 1}, "status", {data_type => "text",    is_nullable => 1},
);

# 设置主键
__PACKAGE__->set_primary_key("ip", "module");

=head1 RELATIONSHIPS

=head2 device

Returns the entry from the C<device> table on which this power module was discovered.

=cut

# 定义关联关系：设备
# 返回发现此功率模块的设备表条目
__PACKAGE__->belongs_to(device => 'App::Netdisco::DB::Result::Device', 'ip');

=head2 ports

Returns the set of PoE ports associated with a power module.

=cut

# 定义关联关系：端口
# 返回与功率模块关联的PoE端口集合
__PACKAGE__->has_many(
  ports => 'App::Netdisco::DB::Result::DevicePortPower',
  {'foreign.ip' => 'self.ip', 'foreign.module' => 'self.module',}
);

1;
