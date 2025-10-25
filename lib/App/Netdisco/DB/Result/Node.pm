use utf8;
package App::Netdisco::DB::Result::Node;

# 节点结果类
# 提供网络节点信息的管理模型

use strict;
use warnings;

use NetAddr::MAC;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("node");

# 定义表列
# 包含MAC地址、交换机、端口、活跃状态、OUI、时间信息和VLAN
__PACKAGE__->add_columns(
  "mac",
  {data_type => "macaddr", is_nullable => 0},
  "switch",
  {data_type => "inet", is_nullable => 0},
  "port",
  {data_type => "text", is_nullable => 0},
  "active",
  {data_type => "boolean", is_nullable => 1},
  "oui",
  {data_type => "varchar", is_nullable => 1, is_serializable => 0, size => 9},
  "time_first", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "time_recent", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "time_last", {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => {default_value => \"LOCALTIMESTAMP"},
  },
  "vlan",
  {data_type => "text", is_nullable => 0, default_value => '0'},
);

# 设置主键
__PACKAGE__->set_primary_key("mac", "switch", "port", "vlan");

=head1 RELATIONSHIPS

=head2 device

Returns the single C<device> to which this Node entry was associated at the
time of discovery.

The JOIN is of type LEFT, in case the C<device> is no longer present in the
database but the relation is being used in C<search()>.

=cut

# 定义关联关系：设备
# 返回发现时与此节点条目关联的单个设备
__PACKAGE__->belongs_to(
  device => 'App::Netdisco::DB::Result::Device',
  {'foreign.ip' => 'self.switch'}, {join_type => 'LEFT'}
);

=head2 device_port

Returns the single C<device_port> to which this Node entry was associated at
the time of discovery.

The JOIN is of type LEFT, in case the C<device> is no longer present in the
database but the relation is being used in C<search()>.

=cut

# 定义关联关系：设备端口
# 返回发现时与此节点条目关联的单个设备端口
# 设备端口可能已被删除（重新配置模块？）但节点仍然存在
__PACKAGE__->belongs_to(
  device_port => 'App::Netdisco::DB::Result::DevicePort',
  {'foreign.ip' => 'self.switch', 'foreign.port' => 'self.port'}, {join_type => 'LEFT'}
);

=head2 wireless_port

Returns the single C<wireless_port> to which this Node entry was associated at
the time of discovery.

The JOIN is of type LEFT, in case the C<device> is no longer present in the
database but the relation is being used in C<search()>.

=cut

# 定义关联关系：无线端口
# 返回发现时与此节点条目关联的单个无线端口
__PACKAGE__->belongs_to(
  wireless_port => 'App::Netdisco::DB::Result::DevicePortWireless',
  {'foreign.ip' => 'self.switch', 'foreign.port' => 'self.port'}, {join_type => 'LEFT'}
);

=head2 ips

Returns the set of C<node_ip> entries associated with this Node. That is, the
IP addresses which this MAC address was hosting at the time of discovery.

Note that the Active status of the returned IP entries will all be the same as
the current Node's.

=cut

# 定义关联关系：IP地址
# 返回与此节点关联的node_ip条目集合，即发现时此MAC地址托管的IP地址
__PACKAGE__->has_many(
  ips => 'App::Netdisco::DB::Result::NodeIp',
  {'foreign.mac' => 'self.mac', 'foreign.active' => 'self.active'}
);

=head2 ip4s

Same as C<ips> but for IPv4 only.

=cut

# 定义关联关系：IPv4地址
# 与ips相同但仅适用于IPv4
__PACKAGE__->has_many(
  ip4s => 'App::Netdisco::DB::Result::Virtual::NodeIp4',
  {'foreign.mac' => 'self.mac', 'foreign.active' => 'self.active'}
);

=head2 ip6s

Same as C<ips> but for IPv6 only.

=cut

# 定义关联关系：IPv6地址
# 与ips相同但仅适用于IPv6
__PACKAGE__->has_many(
  ip6s => 'App::Netdisco::DB::Result::Virtual::NodeIp6',
  {'foreign.mac' => 'self.mac', 'foreign.active' => 'self.active'}
);

=head2 netbios

Returns the C<node_nbt> entry associated with this Node if one exists. That
is, the NetBIOS information of this MAC address at the time of discovery.

=cut

# 定义关联关系：NetBIOS
# 返回与此节点关联的node_nbt条目（如果存在），即发现时此MAC地址的NetBIOS信息
__PACKAGE__->might_have(netbios => 'App::Netdisco::DB::Result::NodeNbt', {'foreign.mac' => 'self.mac'});

=head2 wireless

Returns the set of C<node_wireless> entries associated with this Node. That
is, the SSIDs and wireless statistics associated with this MAC address
at the time of discovery.

=cut

# 定义关联关系：无线
# 返回与此节点关联的node_wireless条目集合，即与此MAC地址关联的SSID和无线统计信息
__PACKAGE__->has_many(wireless => 'App::Netdisco::DB::Result::NodeWireless', {'foreign.mac' => 'self.mac'});

=head2 oui

DEPRECATED: USE MANUFACTURER INSTEAD

Returns the C<oui> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the OUI table has not been populated.

=cut

# 定义关联关系：OUI（已弃用）
# 返回与此节点匹配的OUI表条目，用于检索公司名称
__PACKAGE__->belongs_to(oui => 'App::Netdisco::DB::Result::Oui', 'oui', {join_type => 'LEFT'});

=head2 manufacturer

Returns the C<manufacturer> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the Manufacturer table has not been populated.

=cut

# 定义关联关系：制造商
# 返回与此节点匹配的制造商表条目，用于检索公司名称
__PACKAGE__->belongs_to(
  manufacturer => 'App::Netdisco::DB::Result::Manufacturer',
  {'foreign.base' => 'self.oui',}, {join_type => 'LEFT'}
);

=head1 ADDITIONAL COLUMNS

=head2 time_first_stamp

Formatted version of the C<time_first> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

# 首次时间戳方法
# 返回time_first字段的格式化版本，精确到分钟
sub time_first_stamp { return (shift)->get_column('time_first_stamp') }

=head2 time_last_stamp

Formatted version of the C<time_last> field, accurate to the minute.

The format is somewhat like ISO 8601 or RFC3339 but without the middle C<T>
between the date stamp and time stamp. That is:

 2012-02-06 12:49

=cut

# 最后时间戳方法
# 返回time_last字段的格式化版本，精确到分钟
sub time_last_stamp { return (shift)->get_column('time_last_stamp') }

=head2 net_mac

Returns the C<mac> column instantiated into a L<NetAddr::MAC> object.

=cut

# 网络MAC方法
# 将mac列实例化为NetAddr::MAC对象
sub net_mac { return NetAddr::MAC->new(mac => ((shift)->mac || '')) }

1;
