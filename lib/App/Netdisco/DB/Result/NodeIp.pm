use utf8;
package App::Netdisco::DB::Result::NodeIp;

# 节点IP结果类
# 提供网络节点IP地址信息的管理模型

use strict;
use warnings;

use NetAddr::MAC;

use base 'App::Netdisco::DB::Result';
__PACKAGE__->table("node_ip");
# 定义表列
# 包含MAC地址、IP地址、DNS、活跃状态、时间信息和路由器信息
__PACKAGE__->add_columns(
  "mac",
  { data_type => "macaddr", is_nullable => 0 },
  "ip",
  { data_type => "inet", is_nullable => 0 },
  "dns",
  { data_type => "text", is_nullable => 1 },
  "active",
  { data_type => "boolean", is_nullable => 1 },
  "time_first",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "time_last",
  {
    data_type     => "timestamp",
    default_value => \"LOCALTIMESTAMP",
    is_nullable   => 1,
    original      => { default_value => \"LOCALTIMESTAMP" },
  },
  "seen_on_router_first",
  { data_type => "jsonb", is_nullable => 0, default_value => \"{}" },
  "seen_on_router_last",
  { data_type => "jsonb", is_nullable => 0, default_value => \"{}" },
  "vrf",
  { data_type => "text", is_nullable => 0, default => '' },
);

# 设置主键
__PACKAGE__->set_primary_key("mac", "ip", "vrf");



=head1 RELATIONSHIPS

=head2 oui

DEPRECATED: USE MANUFACTURER INSTEAD

Returns the C<oui> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the OUI table has not been populated.

=cut

# 定义关联关系：OUI（已弃用）
# 返回与此节点匹配的OUI表条目，用于检索公司名称
__PACKAGE__->belongs_to( oui => 'App::Netdisco::DB::Result::Oui',
    sub {
        my $args = shift;
        return {
            "$args->{foreign_alias}.oui" =>
              { '=' => \"substring(cast($args->{self_alias}.mac as varchar) for 8)" }
        };
    },
    { join_type => 'LEFT' }
);

=head2 manufacturer

Returns the C<manufacturer> table entry matching this Node. You can then join on this
relation and retrieve the Company name from the related table.

The JOIN is of type LEFT, in case the Manufacturer table has not been populated.

=cut

# 定义关联关系：制造商
# 返回与此节点匹配的制造商表条目，用于检索公司名称
__PACKAGE__->belongs_to( manufacturer => 'App::Netdisco::DB::Result::Manufacturer',
  sub {
      my $args = shift;
      return {
        "$args->{foreign_alias}.range" => { '@>' =>
          \qq{('x' || lpad( translate( $args->{self_alias}.mac ::text, ':', ''), 16, '0')) ::bit(64) ::bigint} },
      };
  },
  { join_type => 'LEFT' }
);

=head2 router

Returns the C<device> table entry matching this Node's router. You can then join on
this relation and retrieve the Device DNS name.

The JOIN is of type LEFT, in case there's no recorded router on this record.

=cut

# 定义关联关系：路由器
# 返回与此节点路由器匹配的设备表条目，用于检索设备DNS名称
__PACKAGE__->belongs_to( router => 'App::Netdisco::DB::Result::Device',
  sub {
      my $args = shift;
      return {
        "host($args->{foreign_alias}.ip)" => { '=' =>
          \q{(SELECT key FROM json_each_text(seen_on_router_last::json) ORDER BY value::timestamp DESC LIMIT 1)} },
      };
  },
  { join_type => 'LEFT' }
);

=head2 node_ips

Returns the set of all C<node_ip> entries which are associated together with
this IP. That is, all the IP addresses hosted on the same interface (MAC
address) as the current Node IP entry.

Note that the set will include the original Node IP object itself. If you wish
to find the I<other> IPs excluding this one, see the C<ip_aliases> helper
routine, below.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

=cut

# 定义关联关系：节点IP
# 返回与此IP关联的所有node_ip条目集合，即同一接口（MAC地址）上托管的所有IP地址
__PACKAGE__->has_many( node_ips => 'App::Netdisco::DB::Result::NodeIp',
  { 'foreign.mac' => 'self.mac' } );

=head2 nodes

Returns the set of C<node> entries associated with this IP. That is, all the
MAC addresses recorded which have ever hosted this IP Address.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

See also the C<node_sightings> helper routine, below.

=cut

# 定义关联关系：节点
# 返回与此IP关联的节点条目集合，即曾经托管此IP地址的所有MAC地址
__PACKAGE__->has_many( nodes => 'App::Netdisco::DB::Result::Node',
  { 'foreign.mac' => 'self.mac' }, { order_by => { '-desc' => 'time_last' }} );

=head2 netbios

Returns the set of C<node_nbt> entries associated with the MAC of this IP.
That is, all the NetBIOS entries recorded which shared the same MAC with this
IP Address.

=cut

# 定义关联关系：NetBIOS
# 返回与此IP的MAC地址关联的node_nbt条目集合，即与此IP地址共享相同MAC的所有NetBIOS条目
__PACKAGE__->has_many( netbios => 'App::Netdisco::DB::Result::NodeNbt',
  { 'foreign.mac' => 'self.mac' } );

my $search_attr = {
    order_by => {'-desc' => 'time_last'},
    '+columns' => {
      time_first_stamp => \"to_char(time_first, 'YYYY-MM-DD HH24:MI')",
      time_last_stamp => \"to_char(time_last, 'YYYY-MM-DD HH24:MI')",
    },
};

=head2 ip_aliases( \%cond, \%attrs? )

Returns the set of other C<node_ip> entries hosted on the same interface (MAC
address) as the current Node IP, excluding the current IP itself.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

=over 4

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=back

=cut

# IP别名方法
# 返回与当前节点IP托管在同一接口（MAC地址）上的其他node_ip条目集合，排除当前IP本身
sub ip_aliases {
    my ($row, $cond, $attrs) = @_;

    my $rs = $row->node_ips({ip  => { '!=' => $row->ip }});

    return $rs
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

=head2 node_sightings( \%cond, \%attrs? )

Returns the set of C<node> entries associated with this IP. That is, all the
MAC addresses recorded which have ever hosted this IP Address.

Remember you can pass a filter to this method to find only active or inactive
nodes, but do take into account that both the C<node> and C<node_ip> tables
include independent C<active> fields.

=over 4

=item *

Results are ordered by time last seen.

=item *

Additional columns C<time_first_stamp> and C<time_last_stamp> provide
preformatted timestamps of the C<time_first> and C<time_last> fields.

=item *

A JOIN is performed on the Device table and the Device DNS column prefetched.

=back

=cut

# 节点发现方法
# 返回与此IP关联的节点条目集合，即曾经托管此IP地址的所有MAC地址
sub node_sightings {
    my ($row, $cond, $attrs) = @_;

    return $row
      ->nodes({}, {
        '+columns' => [qw/ device.dns device.name /],
        join => 'device',
      })
      ->search_rs({}, $search_attr)
      ->search($cond, $attrs);
}

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
sub time_last_stamp  { return (shift)->get_column('time_last_stamp')  }

=head2 router_ip

Returns the router IP that most recently reported this MAC-IP pair.

=cut

# 路由器IP方法
# 返回最近报告此MAC-IP对的路由器IP
sub router_ip { return (shift)->get_column('router_ip') }

=head2 router_name

Returns the router DNS or SysName that most recently reported this MAC-IP pair.

May be blank if there's no SysName or DNS name, so you have C<router_ip> as well.

=cut

# 路由器名称方法
# 返回最近报告此MAC-IP对的路由器DNS或SysName
sub router_name { return (shift)->get_column('router_name') }

=head2 net_mac

Returns the C<mac> column instantiated into a L<NetAddr::MAC> object.

=cut

# 网络MAC方法
# 将mac列实例化为NetAddr::MAC对象
sub net_mac { return NetAddr::MAC->new(mac => ((shift)->mac || '')) }

1;
