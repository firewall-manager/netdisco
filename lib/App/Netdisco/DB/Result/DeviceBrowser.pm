use utf8;
package App::Netdisco::DB::Result::DeviceBrowser;

# 设备浏览器结果类
# 提供设备SNMP对象浏览器数据的管理模型

use strict;
use warnings;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("device_browser");
# 定义表列
# 包含设备IP、OID和SNMP对象值信息
__PACKAGE__->add_columns(
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "oid",
  { data_type => "text", is_nullable => 0 },
  "oid_parts",
  { data_type => "text", is_nullable => 0 },
  "value",
  { data_type => "jsonb", is_nullable => 1, default_value => \q{[""]} },
);

# 设置主键
__PACKAGE__->set_primary_key("ip", "oid");

=head1 RELATIONSHIPS

=head2 snmp_object

Returns the SNMP Object table entry to which the given row is related. The
idea is that you always get the SNMP Object row data even if the Device
Browser table doesn't have any walked data.

However you probably want to use the C<snmp_object> method in the
C<DeviceBrowser> ResultSet instead, so you can pass the IP address.

=cut

# 定义关联关系：SNMP对象
# 返回与此行相关的SNMP对象表条目
__PACKAGE__->belongs_to(
  snmp_object => 'App::Netdisco::DB::Result::SNMPObject',
  sub {
    my $args = shift;
    return {
        "$args->{self_alias}.oid" => { -ident => "$args->{foreign_alias}.oid" },
        "$args->{self_alias}.ip" => { '=' => \'?' },
    };
  },
  { join_type => 'RIGHT' }
);

# 定义关联关系：OID字段
# 通过OID关联到SNMP对象表
__PACKAGE__->belongs_to( oid_fields => 'App::Netdisco::DB::Result::SNMPObject', 'oid', { join_type => 'left' } );

1;
