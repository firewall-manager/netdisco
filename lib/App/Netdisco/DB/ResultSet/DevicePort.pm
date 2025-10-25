package App::Netdisco::DB::ResultSet::DevicePort;

# 设备端口结果集类
# 提供设备端口相关的数据库查询功能

use base 'App::Netdisco::DB::ResultSet';

use strict;
use warnings;

use Try::Tiny;
require Dancer::Logger;

__PACKAGE__->load_components(qw/
  +App::Netdisco::DB::ExplicitLocking
/);

=head1 ADDITIONAL METHODS

=head2 with_times

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item lastchange_stamp

=back

=cut

# 带时间戳
# 为任何search()添加时间相关的合成列
sub with_times {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { lastchange_stamp =>
          \("to_char(device.last_discover - (device.uptime - me.lastchange) / 100 * interval '1 second', "
            ."'YYYY-MM-DD HH24:MI:SS')") },
        join => 'device',
      });
}

=head2 with_is_free

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item is_free

=back

In the C<$cond> hash (the first parameter) pass in the C<age_num> which must
be an integer, and the C<age_unit> which must be a string of either C<days>,
C<weeks>, C<months> or C<years>.

=cut

# 带空闲状态
# 为任何search()添加空闲状态相关的合成列
sub with_is_free {
  my ($rs, $cond, $attrs) = @_;

  my $interval = (delete $cond->{age_num}) .' '. (delete $cond->{age_unit});

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { is_free =>
          # 注意：此查询在`git grep 'THREE PLACES'`中
          \["me.up_admin = 'up' AND me.up != 'up' AND "
              ."(me.type IS NULL OR me.type !~* '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)\$') AND "
              ."((age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime/100))::timestamp) < ?::interval "
              ."AND (last_node.time_last IS NULL OR age(LOCALTIMESTAMP, last_node.time_last) > ?::interval)) "
              ."OR age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime - me.lastchange)/100)::timestamp) > ?::interval)",
            [{} => $interval],[ {} => $interval],[ {} => $interval]] },
        join => [qw/device last_node/],
      });
}

=head2 only_free_ports

This is a modifier for any C<search()> (including the helpers below) which
will restrict results based on whether the port is considered "free".

In the C<$cond> hash (the first parameter) pass in the C<age_num> which must
be an integer, and the C<age_unit> which must be a string of either C<days>,
C<weeks>, C<months> or C<years>.

=cut

# 仅空闲端口
# 基于端口是否被认为是"空闲"来限制结果
sub only_free_ports {
  my ($rs, $cond, $attrs) = @_;

  my $interval = (delete $cond->{age_num}) .' '. (delete $cond->{age_unit});

  return $rs
    ->search_rs($cond, $attrs)
    ->search(
      {
        # 注意：此查询在`git grep 'THREE PLACES'`中
        'me.up_admin' => 'up',
        'me.up'       => { '!=' => 'up' },
        'me.type' => [ '-or' =>
          { '=' => undef },
          { '!~*' => '^(53|ieee8023adLag|propVirtual|l2vlan|l3ipvlan|135|136|137)$' },
        ],
        -or => [
          -and => [
            \["age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime/100))::timestamp) < ?::interval",
              [{} => $interval]],
            -or => [
              'last_node.time_last' => undef,
              \["age(LOCALTIMESTAMP, last_node.time_last) > ?::interval", [{} => $interval]],
            ]
          ],
          \["age(LOCALTIMESTAMP, to_timestamp(extract(epoch from device.last_discover) - (device.uptime - me.lastchange)/100)::timestamp) > ?::interval",
            [{} => $interval]],
        ],
      },{ join => [qw/device last_node/] },
    );
}

=head2 with_properties

This is a modifier for any C<search()> which
will add the following additional synthesized columns to the result set:

=over 4

=item error_disable_cause

=item remote_is_discoverable (boolean)

=item remote_is_wap (boolean)

=item remote_is_phone (boolean)

=item remote_dns

=item ifindex

=back

=cut

# 带属性
# 为任何search()添加端口属性相关的合成列
sub with_properties {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [qw/
          properties.error_disable_cause
          properties.remote_is_discoverable
          properties.remote_is_wap
          properties.remote_is_phone
          properties.remote_dns
          properties.ifindex
          properties.pae_authconfig_port_control
          properties.pae_authconfig_state
          properties.pae_authconfig_port_status
          properties.pae_authsess_user
          properties.pae_authsess_mab
          properties.pae_last_eapol_frame_source
        /],
        '+as' => [qw/
          error_disable_cause
          remote_is_discoverable remote_is_wap remote_is_phone remote_dns
          ifindex 
          pae_authconfig_port_control 
          pae_authconfig_state 
          pae_authconfig_port_status
          pae_authsess_user 
          pae_authsess_mab
          pae_last_eapol_frame_source
        /],
        join => 'properties',
      });
}

=head2 with_remote_inventory

This is a modifier for any C<search()> which
will add the following additional synthesized columns to the result set:

=over 4

=item remote_vendor

=item remote_model

=item remote_os_ver

=item remote_serial

=back

=cut

# 带远程清单
# 为任何search()添加远程设备清单相关的合成列
sub with_remote_inventory {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+select' => [qw/
          properties.remote_vendor
          properties.remote_model
          properties.remote_os_ver
          properties.remote_serial
        /],
        '+as' => [qw/
          remote_vendor remote_model remote_os_ver remote_serial
        /],
        join => 'properties',
      });
}

=head2 with_vlan_count

This is a modifier for any C<search()> (including the helpers below) which
will add the following additional synthesized columns to the result set:

=over 4

=item vlan_count

=back

=cut

# 带VLAN计数
# 为任何search()添加VLAN计数相关的合成列
sub with_vlan_count {
  my ($rs, $cond, $attrs) = @_;

  return $rs
    ->search_rs($cond, $attrs)
    ->search({},
      {
        '+columns' => { vlan_count =>
          $rs->result_source->schema->resultset('DevicePortVlan')
            ->search(
              {
                'dpv.ip'   => { -ident => 'me.ip' },
                'dpv.port' => { -ident => 'me.port' },
              },
              { alias => 'dpv' }
            )->count_rs->as_query
        },
      });
}

=head1 SPECIAL METHODS

=head2 delete( \%options? )

Overrides the built-in L<DBIx::Class> delete method to more efficiently
handle the removal or archiving of nodes.

=cut

sub _plural { (shift || 0) == 1 ? 'entry' : 'entries' };

sub delete {
  my $self = shift;

  my $schema = $self->result_source->schema;
  my $ports = $self->search(undef, { columns => 'ip' });

  my $ip = undef;
  {
    no autovivification;
    try { $ip ||= ${ $ports->{attrs}->{where}->{ip}->{'-in'} }->[1]->[1] };
    try { $ip ||= $ports->{attrs}->{where}->{'me.ip'} };
  }
  $ip ||= 'netdisco';

  foreach my $set (qw/
    DevicePortPower
    DevicePortProperties
    DevicePortSsid
    DevicePortVlan
    DevicePortWireless
  /) {
      my $gone = $schema->resultset($set)->search(
        { ip => { '-in' => $ports->as_query }},
      )->delete;

      Dancer::Logger::debug( sprintf( ' [%s] db/ports - removed %d port %s from %s',
        $ip, $gone, _plural($gone), $set ) ) if defined Dancer::Logger::logger();
  }

  $schema->resultset('Node')->search(
    { switch => { '-in' => $ports->as_query }},
  )->delete(@_);

  # 现在让DBIC做它的事情
  return $self->next::method();
}

1;
